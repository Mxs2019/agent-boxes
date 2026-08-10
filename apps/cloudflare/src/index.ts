import PostalMime from "postal-mime";
import { createAccount, deleteAccount } from "./accounts";
import {
  createAgent,
  listAgents,
  renameAgent,
  replaceAgentKey,
  revealAgentKey,
  revokeAgent,
} from "./agents";
import { authenticateAccount, authenticateAgent } from "./auth";
import { createCard, toCard } from "./cards";
import { HttpError } from "./errors";
import {
  createFeedback,
  deleteFeedback,
  listFeedback,
  resolveFeedback,
  updateFeedback,
} from "./feedback";
import {
  json,
  MAX_CARD_BYTES,
  parseNonnegativeInteger,
  readLimitedBody,
  secureAssetResponse,
} from "./http";
import { createInbox, listInboxes, renameInbox, revokeInbox } from "./inboxes";
import { handleMcp, type McpToolResult } from "./mcp";
import { resetOnboardingCards } from "./onboarding";
import { handleCardUpdateBatch, makePushPreview } from "./push";
import type {
  AccountRow,
  CardRow,
  CardUpdateMessage,
  CreateCardJson,
  DeviceRegistration,
  InboxRow,
} from "./types";

const MAX_EMAIL_BYTES = MAX_CARD_BYTES + 128 * 1024;

interface AgentBoxEnv extends Env {
  AGENT_KEY_ENCRYPTION_KEY?: string;
  ACCOUNT_RATE_LIMITER: RateLimit;
  ASSETS: Fetcher;
}

function log(event: string, fields: Record<string, unknown>): void {
  console.log(JSON.stringify({ event, ...fields }));
}

function agentKeyEncryptionSecret(env: Env): string {
  const value = (env as AgentBoxEnv).AGENT_KEY_ENCRYPTION_KEY;
  if (!value) throw new Error("AGENT_KEY_ENCRYPTION_KEY is not configured.");
  return value;
}

async function enforceIngestionLimits(
  env: Env,
  account: AccountRow,
  agentId: string,
): Promise<void> {
  const rateLimit = await env.CARD_RATE_LIMITER.limit({ key: `create:${agentId}` });
  if (!rateLimit.success) {
    throw new HttpError(429, "rate_limited", "Too many cards were sent. Try again later.");
  }

  const oneHourAgo = Math.floor(Date.now() / 1000) - 60 * 60;
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM cards WHERE account_id = ?1 AND created_at >= ?2",
  )
    .bind(account.id, oneHourAgo)
    .first<{ count: number }>();
  const limit = Number(env.CARDS_PER_HOUR) || 120;
  if ((row?.count ?? 0) >= limit) {
    throw new HttpError(
      429,
      "hourly_limit_reached",
      "This destination reached its hourly card limit.",
    );
  }
}

async function enforceAgentAuthenticationLimit(request: Request, env: Env): Promise<void> {
  const address = request.headers.get("cf-connecting-ip") ?? "unknown";
  const result = await env.CARD_RATE_LIMITER.limit({ key: `agent-auth:${address}` });
  if (!result.success) {
    throw new HttpError(429, "rate_limited", "Too many card requests. Try again later.");
  }
}

async function handleCreateCard(request: Request, env: Env): Promise<Response> {
  await enforceAgentAuthenticationLimit(request, env);
  const { account, agent } = await authenticateAgent(request, env.DB);
  await enforceIngestionLimits(env, account, agent.id);

  const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  const body = await readLimitedBody(request);
  let payload: CreateCardJson;

  if (contentType === "application/json") {
    try {
      payload = JSON.parse(body) as CreateCardJson;
    } catch {
      throw new HttpError(400, "invalid_json", "The request body must contain valid JSON.");
    }
    if (!payload || Array.isArray(payload) || typeof payload !== "object") {
      throw new HttpError(400, "invalid_json", "The request body must contain a JSON object.");
    }
    if (typeof payload.html !== "string") {
      throw new HttpError(400, "missing_html", "html is required and must be a string.");
    }
  } else if (contentType === "text/html") {
    payload = {
      html: body,
    } as CreateCardJson;
  } else {
    throw new HttpError(415, "unsupported_media_type", "Use application/json or text/html.");
  }

  const result = await createCard(env.DB, account, {
    title: request.headers.get("x-card-title") ?? payload.title,
    html: payload.html,
    showAt: request.headers.get("x-card-show-at") ?? payload.show_at,
    showIn: request.headers.get("x-card-show-in") ?? payload.show_in,
    expiresIn:
      request.headers.get("x-card-expires-in") ??
      request.headers.get("x-card-ttl") ??
      payload.expires_in,
    expiresAt: request.headers.get("x-card-expires-at") ?? payload.expires_at,
    source: "api",
    sourceName: agent.name,
    agentId: agent.id,
    idempotencyKey: request.headers.get("idempotency-key") ?? undefined,
    metadata: payload.metadata,
  });
  const { card } = result;
  if (result.created) {
    await env.CARD_UPDATE_QUEUE.send({
      account_id: account.id,
      card_id: card.id,
      preview: makePushPreview(card.plain_text),
      source_name: card.source_name,
      title: card.title,
    });
  }

  log("card_created", {
    card_id: card.id,
    account_id: account.id,
    agent_id: agent.id,
    source: "api",
  });
  return json(
    {
      id: card.id,
      sequence: card.sequence,
      created_at: card.created_at,
      show_at: card.show_at,
      expires_at: card.expires_at,
    },
    201,
  );
}

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function textEmailToHTML(value: string): string {
  return value
    .trim()
    .split(/\n{2,}/)
    .map((paragraph) => `<p>${escapeHTML(paragraph).replaceAll("\n", "<br>")}</p>`)
    .join("\n");
}

function emailParts(address: string): { localPart: string; domain: string } | null {
  const normalized = address.trim().toLowerCase();
  const separator = normalized.lastIndexOf("@");
  if (separator <= 0 || separator === normalized.length - 1) return null;
  return {
    localPart: normalized.slice(0, separator).split("+", 1)[0],
    domain: normalized.slice(separator + 1),
  };
}

interface EmailDestination {
  account: AccountRow;
  inbox: InboxRow;
}

async function resolveEmailDestination(
  db: D1Database,
  address: string,
  inboxDomain: string,
): Promise<EmailDestination> {
  const parts = emailParts(address);
  if (!parts || parts.domain !== inboxDomain.toLowerCase()) {
    throw new HttpError(404, "email_destination_not_found", "The card destination does not exist.");
  }

  const row = await db
    .prepare(
      `SELECT
         inboxes.id, inboxes.account_id, inboxes.name, inboxes.local_part,
         inboxes.created_at, inboxes.revoked_at,
         accounts.account_key_hash, accounts.created_at AS account_created_at
       FROM inboxes
       JOIN accounts ON accounts.id = inboxes.account_id
       WHERE inboxes.local_part = ?1`,
    )
    .bind(parts.localPart)
    .first<InboxRow & { account_key_hash: string; account_created_at: number }>();
  if (!row) {
    throw new HttpError(404, "email_destination_not_found", "The card destination does not exist.");
  }
  if (row.revoked_at !== null) {
    throw new HttpError(410, "inbox_revoked", "This inbox has been revoked.");
  }
  return {
    inbox: row,
    account: {
      id: row.account_id,
      account_key_hash: row.account_key_hash,
      created_at: row.account_created_at,
    },
  };
}

async function handleEmail(message: ForwardableEmailMessage, env: Env): Promise<void> {
  if (message.rawSize > MAX_EMAIL_BYTES) {
    message.setReject("The email is too large for a card.");
    return;
  }

  try {
    const destination = await resolveEmailDestination(env.DB, message.to, env.INBOX_EMAIL_DOMAIN);
    const { account, inbox } = destination;
    await enforceIngestionLimits(env, account, inbox.id);
    const parsed = await PostalMime.parse(message.raw);
    const text = parsed.text?.trim() ?? "";
    const html = parsed.html?.trim() || textEmailToHTML(text);
    if (!html) throw new HttpError(400, "missing_html", "The email body is empty.");

    const result = await createCard(env.DB, account, {
      title: parsed.subject?.trim() || "Email from sender",
      html,
      expiresIn: "24h",
      source: "email",
      sourceName: message.from,
      idempotencyKey: message.headers.get("message-id") ?? undefined,
      metadata: { inbox_id: inbox.id, inbox_name: inbox.name },
    });
    const { card } = result;
    if (result.created) {
      await env.CARD_UPDATE_QUEUE.send({
        account_id: account.id,
        card_id: card.id,
        preview: makePushPreview(card.plain_text),
        source_name: card.source_name,
        title: card.title,
      });
    }
    log("card_created", {
      card_id: card.id,
      account_id: account.id,
      source: "email",
      content_trust: "untrusted",
      inbox_id: inbox.id,
    });
  } catch (error) {
    if (error instanceof HttpError) {
      log("email_rejected", { code: error.code, status: error.status });
      message.setReject(error.message);
      return;
    }
    log("email_parsing_failed", { recipient: message.to });
    throw error;
  }
}

async function handleCreateAgent(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const body = await readLimitedBody(request, 16 * 1024);
  let payload: { name?: unknown };
  try {
    payload = JSON.parse(body) as { name?: unknown };
  } catch {
    throw new HttpError(400, "invalid_json", "The request body must contain valid JSON.");
  }
  if (!payload || Array.isArray(payload) || typeof payload !== "object") {
    throw new HttpError(400, "invalid_json", "The request body must contain a JSON object.");
  }

  const result = await createAgent(env.DB, account, payload.name, agentKeyEncryptionSecret(env));
  log("agent_created", { agent_id: result.agent.id, account_id: account.id });
  const origin = new URL(request.url).origin;
  return json(
    {
      agent: result.agent,
      agent_key: result.agentKey,
      mcp_url: `${origin}/mcp`,
      post_url: `${origin}/v1/cards`,
    },
    201,
  );
}

async function handleCreateAccount(request: Request, env: Env): Promise<Response> {
  const address = request.headers.get("cf-connecting-ip") ?? "unknown";
  const rateLimit = await (env as AgentBoxEnv).ACCOUNT_RATE_LIMITER.limit({
    key: `account-create:${address}`,
  });
  if (!rateLimit.success) {
    throw new HttpError(429, "rate_limited", "Too many accounts were created. Try again later.");
  }

  const result = await createAccount(env.DB);
  try {
    await resetOnboardingCards(env.DB, result.account, agentKeyEncryptionSecret(env));
  } catch (error) {
    await deleteAccount(env.DB, result.account.id);
    throw error;
  }
  log("account_created", { account_id: result.account.id });
  return json({ account_key: result.accountKey }, 201);
}

async function handleResetOnboarding(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const cards = await resetOnboardingCards(env.DB, account, agentKeyEncryptionSecret(env));
  log("onboarding_reset", { account_id: account.id, card_count: cards.length });
  return json({ cards: cards.map((card) => ({ id: card.id, sequence: card.sequence })) }, 201);
}

async function handleListAgents(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  return json({ agents: await listAgents(env.DB, account) });
}

async function handleRevokeAgent(request: Request, env: Env, agentId: string): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  await revokeAgent(env.DB, account, agentId);
  log("agent_revoked", { agent_id: agentId, account_id: account.id });
  return new Response(null, { status: 204 });
}

async function handleRevealAgentKey(
  request: Request,
  env: Env,
  agentId: string,
): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const agentKey = await revealAgentKey(env.DB, account, agentId, agentKeyEncryptionSecret(env));
  log("agent_key_revealed", { agent_id: agentId, account_id: account.id });
  return json({ agent_key: agentKey });
}

async function handleReplaceAgentKey(
  request: Request,
  env: Env,
  agentId: string,
): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const agentKey = await replaceAgentKey(env.DB, account, agentId, agentKeyEncryptionSecret(env));
  log("agent_key_replaced", { agent_id: agentId, account_id: account.id });
  return json({ agent_key: agentKey });
}

async function handleRenameAgent(request: Request, env: Env, agentId: string): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const payload = await readNamePayload(request);
  return json({ agent: await renameAgent(env.DB, account, agentId, payload.name) });
}

async function readNamePayload(request: Request): Promise<{ name?: unknown }> {
  const body = await readLimitedBody(request, 16 * 1024);
  let payload: { name?: unknown };
  try {
    payload = JSON.parse(body) as { name?: unknown };
  } catch {
    throw new HttpError(400, "invalid_json", "The request body must contain valid JSON.");
  }
  if (!payload || Array.isArray(payload) || typeof payload !== "object") {
    throw new HttpError(400, "invalid_json", "The request body must contain a JSON object.");
  }
  return payload;
}

async function handleCreateInbox(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const body = await readLimitedBody(request, 16 * 1024);
  let payload: { name?: unknown };
  try {
    payload = JSON.parse(body) as { name?: unknown };
  } catch {
    throw new HttpError(400, "invalid_json", "The request body must contain valid JSON.");
  }
  if (!payload || Array.isArray(payload) || typeof payload !== "object") {
    throw new HttpError(400, "invalid_json", "The request body must contain a JSON object.");
  }

  const inbox = await createInbox(env.DB, account, payload.name, env.INBOX_EMAIL_DOMAIN);
  log("inbox_created", { inbox_id: inbox.id, account_id: account.id });
  return json({ inbox }, 201);
}

async function handleListInboxes(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  return json({ inboxes: await listInboxes(env.DB, account, env.INBOX_EMAIL_DOMAIN) });
}

async function handleRevokeInbox(request: Request, env: Env, inboxId: string): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  await revokeInbox(env.DB, account, inboxId);
  log("inbox_revoked", { inbox_id: inboxId, account_id: account.id });
  return new Response(null, { status: 204 });
}

async function handleRenameInbox(request: Request, env: Env, inboxId: string): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const payload = await readNamePayload(request);
  const inbox = await renameInbox(env.DB, account, inboxId, payload.name, env.INBOX_EMAIL_DOMAIN);
  return json({ inbox });
}

async function handleSync(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const url = new URL(request.url);
  const after = parseNonnegativeInteger(url.searchParams.get("after"), 0);
  const requestedLimit = parseNonnegativeInteger(url.searchParams.get("limit"), 200);
  const limit = Math.min(Math.max(requestedLimit, 1), 500);

  const result = await env.DB.prepare(
    `WITH latest_changes AS (
      SELECT card_id, MAX(sequence) AS change_sequence
      FROM card_changes
      WHERE account_id = ?1 AND sequence > ?2
      GROUP BY card_id
      ORDER BY change_sequence ASC
      LIMIT ?3
    )
    SELECT cards.*, latest_changes.change_sequence
    FROM latest_changes
    JOIN cards ON cards.id = latest_changes.card_id
    ORDER BY latest_changes.change_sequence ASC`,
  )
    .bind(account.id, after, limit + 1)
    .all<CardRow & { change_sequence: number }>();

  const rows = result.results;
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  let cursor = page.at(-1)?.change_sequence ?? after;

  if (page.length === 0) {
    const current = await env.DB.prepare(
      "SELECT COALESCE(MAX(sequence), 0) AS cursor FROM card_changes WHERE account_id = ?1",
    )
      .bind(account.id)
      .first<{ cursor: number }>();
    cursor = Math.max(after, current?.cursor ?? 0);
  }

  log("sync_requested", { account_id: account.id, after, cursor, card_count: page.length });
  return json({
    cards: page.map(toCard),
    cursor,
    has_more: hasMore,
    server_time: new Date().toISOString(),
  });
}

async function handleClear(request: Request, env: Env, cardId: string): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const clearedAt = Math.floor(Date.now() / 1000);
  let card = await env.DB.prepare(
    `UPDATE cards SET cleared_at = ?1
     WHERE id = ?2 AND account_id = ?3 AND cleared_at IS NULL
     RETURNING *`,
  )
    .bind(clearedAt, cardId, account.id)
    .first<CardRow>();

  card ??= await env.DB.prepare("SELECT * FROM cards WHERE id = ?1 AND account_id = ?2")
    .bind(cardId, account.id)
    .first<CardRow>();
  if (!card) throw new HttpError(404, "card_not_found", "The card does not exist.");

  log("card_cleared", { card_id: card.id, account_id: account.id });
  return json({ id: card.id, cleared_at: toCard(card).cleared_at });
}

async function handleRestore(request: Request, env: Env, cardId: string): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const restoredAt = Math.floor(Date.now() / 1000);
  let card = await env.DB.prepare(
    `UPDATE cards
     SET cleared_at = NULL,
         show_at = NULL,
         expires_at = CASE WHEN expires_at <= ?1 THEN NULL ELSE expires_at END
     WHERE id = ?2 AND account_id = ?3
       AND (cleared_at IS NOT NULL OR show_at IS NOT NULL OR expires_at <= ?1)
     RETURNING *`,
  )
    .bind(restoredAt, cardId, account.id)
    .first<CardRow>();

  card ??= await env.DB.prepare("SELECT * FROM cards WHERE id = ?1 AND account_id = ?2")
    .bind(cardId, account.id)
    .first<CardRow>();
  if (!card) throw new HttpError(404, "card_not_found", "The card does not exist.");

  log("card_restored", { card_id: card.id, account_id: account.id });
  const restored = toCard(card);
  return json({
    id: card.id,
    cleared_at: restored.cleared_at,
    show_at: restored.show_at,
    expires_at: restored.expires_at,
  });
}

async function handleCreateFeedback(request: Request, env: Env, cardId: string): Promise<Response> {
  const feedback = await createFeedback(request, env.DB, cardId);
  log("feedback_created", {
    feedback_id: feedback.id,
    card_id: feedback.card_id,
    agent_id: feedback.agent_id,
  });
  return json({ feedback }, 201);
}

async function handleListFeedback(request: Request, env: Env): Promise<Response> {
  return json({ feedback: await listFeedback(request, env.DB) });
}

async function handleUpdateFeedback(
  request: Request,
  env: Env,
  feedbackId: string,
): Promise<Response> {
  const feedback = await updateFeedback(request, env.DB, feedbackId);
  log("feedback_updated", { feedback_id: feedback.id });
  return json({ feedback });
}

async function handleDeleteFeedback(
  request: Request,
  env: Env,
  feedbackId: string,
): Promise<Response> {
  await deleteFeedback(request, env.DB, feedbackId);
  log("feedback_deleted", { feedback_id: feedbackId });
  return new Response(null, { status: 204 });
}

async function handleResolveFeedback(
  request: Request,
  env: Env,
  feedbackId: string,
): Promise<Response> {
  const feedback = await resolveFeedback(request, env.DB, feedbackId);
  log("feedback_resolved", {
    feedback_id: feedback.id,
    agent_id: feedback.agent_id,
  });
  return json({ feedback });
}

async function handleDeviceRegistration(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  const body = await readLimitedBody(request, 16 * 1024);
  let payload: DeviceRegistration;
  try {
    payload = JSON.parse(body) as DeviceRegistration;
  } catch {
    throw new HttpError(400, "invalid_json", "The request body must contain valid JSON.");
  }
  if (!payload || typeof payload.id !== "string" || !payload.id.trim()) {
    throw new HttpError(400, "invalid_device", "id is required.");
  }
  if (typeof payload.apns_token !== "string" || !/^[a-f0-9]{32,200}$/i.test(payload.apns_token)) {
    throw new HttpError(400, "invalid_device", "apns_token is not valid.");
  }
  const apnsEnvironment = payload.apns_environment ?? "production";
  if (apnsEnvironment !== "development" && apnsEnvironment !== "production") {
    throw new HttpError(400, "invalid_device", "apns_environment is not valid.");
  }
  if (payload.id.length > 200) throw new HttpError(400, "invalid_device", "id is too long.");

  const deviceId = payload.id.trim();
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    `INSERT INTO devices (
       id, account_id, apns_token, apns_environment, created_at, last_seen_at
     ) VALUES (?1, ?2, ?3, ?4, ?5, ?5)
     ON CONFLICT(id) DO UPDATE SET
       apns_token = excluded.apns_token,
       apns_environment = excluded.apns_environment,
       last_seen_at = excluded.last_seen_at
     WHERE devices.account_id = excluded.account_id`,
  )
    .bind(deviceId, account.id, payload.apns_token, apnsEnvironment, now)
    .run();

  const owner = await env.DB.prepare("SELECT account_id FROM devices WHERE id = ?1")
    .bind(deviceId)
    .first<{ account_id: string }>();
  if (owner?.account_id !== account.id) {
    throw new HttpError(
      409,
      "device_already_registered",
      "This device is registered to another account. Remove it from that account first.",
    );
  }

  return new Response(null, { status: 204 });
}

async function handleDeleteAccount(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  await deleteAccount(env.DB, account.id);
  log("account_deleted", { account_id: account.id });
  return new Response(null, { status: 204 });
}

async function handleDeviceRemoval(
  request: Request,
  env: Env,
  deviceId: string,
): Promise<Response> {
  const account = await authenticateAccount(request, env.DB);
  await env.DB.prepare("DELETE FROM devices WHERE id = ?1 AND account_id = ?2")
    .bind(deviceId, account.id)
    .run();
  return new Response(null, { status: 204 });
}

function rejectUnknownToolArguments(
  argumentsValue: Record<string, unknown>,
  allowed: readonly string[],
): void {
  const unknown = Object.keys(argumentsValue).find((key) => !allowed.includes(key));
  if (unknown) {
    throw new HttpError(400, "invalid_tool_arguments", `Unknown tool argument: ${unknown}.`);
  }
}

function optionalStringToolArgument(
  argumentsValue: Record<string, unknown>,
  name: string,
): string | undefined {
  const value = argumentsValue[name];
  if (value === undefined) return undefined;
  if (typeof value !== "string") {
    throw new HttpError(400, "invalid_tool_arguments", `${name} must be a string.`);
  }
  return value;
}

async function invokeAgentMcpTool(
  request: Request,
  env: Env,
  account: AccountRow,
  agent: { id: string; name: string },
  name: string,
  argumentsValue: Record<string, unknown>,
): Promise<McpToolResult> {
  if (name === "send_card") {
    rejectUnknownToolArguments(argumentsValue, [
      "title",
      "html",
      "show_at",
      "show_in",
      "expires_in",
      "expires_at",
      "idempotency_key",
      "metadata",
    ]);
    if (typeof argumentsValue.html !== "string") {
      throw new HttpError(400, "invalid_tool_arguments", "html is required and must be a string.");
    }
    for (const field of ["show_in", "expires_in"] as const) {
      const value = argumentsValue[field];
      if (value !== undefined && typeof value !== "string" && typeof value !== "number") {
        throw new HttpError(400, "invalid_tool_arguments", `${field} must be a string or number.`);
      }
    }
    const metadata = argumentsValue.metadata;
    if (
      metadata !== undefined &&
      (!metadata || Array.isArray(metadata) || typeof metadata !== "object")
    ) {
      throw new HttpError(400, "invalid_tool_arguments", "metadata must be a JSON object.");
    }

    await enforceIngestionLimits(env, account, agent.id);
    const result = await createCard(env.DB, account, {
      title: optionalStringToolArgument(argumentsValue, "title"),
      html: argumentsValue.html,
      showAt: optionalStringToolArgument(argumentsValue, "show_at"),
      showIn: argumentsValue.show_in as string | number | undefined,
      expiresIn: argumentsValue.expires_in as string | number | undefined,
      expiresAt: optionalStringToolArgument(argumentsValue, "expires_at"),
      source: "api",
      sourceName: agent.name,
      agentId: agent.id,
      idempotencyKey: optionalStringToolArgument(argumentsValue, "idempotency_key"),
      metadata: metadata as Record<string, unknown> | undefined,
    });
    const { card } = result;
    if (result.created) {
      await env.CARD_UPDATE_QUEUE.send({
        account_id: account.id,
        card_id: card.id,
        preview: makePushPreview(card.plain_text),
        source_name: card.source_name,
        title: card.title,
      });
    }
    log("card_created", {
      card_id: card.id,
      account_id: account.id,
      agent_id: agent.id,
      source: "mcp",
    });
    return {
      structuredContent: {
        id: card.id,
        sequence: card.sequence,
        created_at: card.created_at,
        show_at: card.show_at,
        expires_at: card.expires_at,
        created: result.created,
      },
    };
  }

  if (name === "list_feedback") {
    rejectUnknownToolArguments(argumentsValue, ["status"]);
    const status = optionalStringToolArgument(argumentsValue, "status") ?? "unresolved";
    const feedbackURL = new URL("/v1/feedback", request.url);
    feedbackURL.searchParams.set("status", status);
    const feedbackRequest = new Request(feedbackURL, {
      headers: request.headers,
      method: "GET",
    });
    return { structuredContent: { feedback: await listFeedback(feedbackRequest, env.DB) } };
  }

  if (name === "resolve_feedback") {
    rejectUnknownToolArguments(argumentsValue, ["feedback_id"]);
    const feedbackId = optionalStringToolArgument(argumentsValue, "feedback_id");
    if (!feedbackId || !/^feedback_[A-Z0-9]+$/.test(feedbackId)) {
      throw new HttpError(
        400,
        "invalid_tool_arguments",
        "feedback_id is required and must be a feedback ID.",
      );
    }
    return {
      structuredContent: { feedback: await resolveFeedback(request, env.DB, feedbackId) },
    };
  }

  throw new HttpError(400, "unknown_tool", `Unknown tool: ${name}`);
}

async function handleAgentMcp(request: Request, env: Env): Promise<Response> {
  let authentication:
    | Promise<{ account: AccountRow; agent: { id: string; name: string } }>
    | undefined;
  const authenticate = () => {
    authentication ??= (async () => {
      await enforceAgentAuthenticationLimit(request, env);
      return authenticateAgent(request, env.DB);
    })();
    return authentication;
  };
  return handleMcp(request, {
    authenticate: async () => {
      await authenticate();
    },
    instructions:
      "Use send_card to deliver self-contained HTML cards. Before you create or improve a card, use list_feedback to read unresolved user comments. After you address a feedback item, use resolve_feedback. After send_card, tell the user whether the send succeeded. Include the returned card ID and show_at when it is present.",
    invokeTool: async (name, argumentsValue) => {
      const { account, agent } = await authenticate();
      return invokeAgentMcpTool(request, env, account, agent, name, argumentsValue);
    },
  });
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";

  if (request.method === "GET" && path === "/health") return json({ status: "ok" });
  if (path === "/mcp") return handleAgentMcp(request, env);
  if (request.method === "POST" && path === "/v1/accounts") {
    return handleCreateAccount(request, env);
  }
  if (request.method === "DELETE" && path === "/v1/account") {
    return handleDeleteAccount(request, env);
  }
  if (request.method === "POST" && path === "/v1/onboarding/reset") {
    return handleResetOnboarding(request, env);
  }
  if (request.method === "POST" && path === "/v1/cards") {
    return handleCreateCard(request, env);
  }
  if (request.method === "GET" && path === "/v1/sync") return handleSync(request, env);
  if (request.method === "GET" && path === "/v1/feedback") {
    return handleListFeedback(request, env);
  }
  if (request.method === "GET" && path === "/v1/agents") {
    return handleListAgents(request, env);
  }
  if (request.method === "POST" && path === "/v1/agents") {
    return handleCreateAgent(request, env);
  }
  if (request.method === "GET" && path === "/v1/inboxes") {
    return handleListInboxes(request, env);
  }
  if (request.method === "POST" && path === "/v1/inboxes") {
    return handleCreateInbox(request, env);
  }
  if (request.method === "POST" && path === "/v1/devices") {
    return handleDeviceRegistration(request, env);
  }

  const deviceMatch = path.match(/^\/v1\/devices\/([^/]+)$/);
  if (request.method === "DELETE" && deviceMatch) {
    return handleDeviceRemoval(request, env, decodeURIComponent(deviceMatch[1]));
  }

  const agentMatch = path.match(/^\/v1\/agents\/(agent_[A-Z0-9]+)$/);
  if (request.method === "DELETE" && agentMatch) {
    return handleRevokeAgent(request, env, agentMatch[1]);
  }
  if (request.method === "PATCH" && agentMatch) {
    return handleRenameAgent(request, env, agentMatch[1]);
  }

  const agentKeyMatch = path.match(/^\/v1\/agents\/(agent_[A-Z0-9]+)\/key$/);
  if (request.method === "GET" && agentKeyMatch) {
    return handleRevealAgentKey(request, env, agentKeyMatch[1]);
  }
  if (request.method === "POST" && agentKeyMatch) {
    return handleReplaceAgentKey(request, env, agentKeyMatch[1]);
  }

  const inboxMatch = path.match(/^\/v1\/inboxes\/(inbox_[A-Z0-9]+)$/);
  if (request.method === "DELETE" && inboxMatch) {
    return handleRevokeInbox(request, env, inboxMatch[1]);
  }
  if (request.method === "PATCH" && inboxMatch) {
    return handleRenameInbox(request, env, inboxMatch[1]);
  }

  const clearMatch = path.match(/^\/v1\/cards\/(card_[A-Z0-9]+)\/clear$/);
  if (request.method === "POST" && clearMatch) return handleClear(request, env, clearMatch[1]);

  const restoreMatch = path.match(/^\/v1\/cards\/(card_[A-Z0-9]+)\/restore$/);
  if (request.method === "POST" && restoreMatch) {
    return handleRestore(request, env, restoreMatch[1]);
  }

  const cardFeedbackMatch = path.match(/^\/v1\/cards\/(card_[A-Z0-9]+)\/feedback$/);
  if (request.method === "POST" && cardFeedbackMatch) {
    return handleCreateFeedback(request, env, cardFeedbackMatch[1]);
  }

  const feedbackMatch = path.match(/^\/v1\/feedback\/(feedback_[A-Z0-9]+)$/);
  if (request.method === "PATCH" && feedbackMatch) {
    return handleUpdateFeedback(request, env, feedbackMatch[1]);
  }
  if (request.method === "DELETE" && feedbackMatch) {
    return handleDeleteFeedback(request, env, feedbackMatch[1]);
  }

  const resolveFeedbackMatch = path.match(/^\/v1\/feedback\/(feedback_[A-Z0-9]+)\/resolve$/);
  if (request.method === "POST" && resolveFeedbackMatch) {
    return handleResolveFeedback(request, env, resolveFeedbackMatch[1]);
  }

  if (request.method === "GET" || request.method === "HEAD") {
    const asset = await (env as AgentBoxEnv).ASSETS.fetch(request);
    if (asset.status !== 404) return secureAssetResponse(asset);
  }

  throw new HttpError(404, "not_found", "The endpoint does not exist.");
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HttpError) {
        if (error.status >= 400)
          log("request_rejected", { code: error.code, status: error.status });
        return json({ error: { code: error.code, message: error.message } }, error.status);
      }
      console.error(error);
      return json(
        { error: { code: "internal_error", message: "The server could not process the request." } },
        500,
      );
    }
  },
  async email(message, env): Promise<void> {
    await handleEmail(message, env);
  },
  async queue(batch, env): Promise<void> {
    await handleCardUpdateBatch(batch, env);
  },
} satisfies ExportedHandler<Env, CardUpdateMessage>;
