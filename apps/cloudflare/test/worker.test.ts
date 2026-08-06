import { env } from "cloudflare:workers";
import { applyD1Migrations, type D1Migration } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import worker from "../src/index";
import { hashToken } from "../src/auth";

const TOKEN = "ab_account_" + "test".repeat(8);
const testEnv = env as Env & { TEST_MIGRATIONS: D1Migration[] };
let agentKey = "";
let agentId = "";

async function call(path: string, init?: RequestInit): Promise<Response> {
  const request = new Request(`https://cards.example.com${path}`, init) as Parameters<
    typeof worker.fetch
  >[0];
  return worker.fetch(request, testEnv);
}

async function deliverEmail(
  raw: string,
  options: { from?: string; to: string; messageId?: string },
): Promise<string | null> {
  let rejection: string | null = null;
  const messageId = options.messageId ?? "<email-test@example.com>";
  const message = {
    from: options.from ?? "sender@example.com",
    to: options.to,
    headers: new Headers({ "message-id": messageId }),
    raw: new Response(raw).body!,
    rawSize: new TextEncoder().encode(raw).byteLength,
    setReject(reason: string) {
      rejection = reason;
    },
  } as unknown as ForwardableEmailMessage;
  await worker.email(message, testEnv);
  return rejection;
}

beforeAll(async () => {
  await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
  await testEnv.DB.prepare(
    "INSERT INTO accounts (id, account_key_hash, created_at) VALUES (?1, ?2, ?3)",
  )
    .bind("account_test", await hashToken(TOKEN), Math.floor(Date.now() / 1000))
    .run();

  const response = await call("/v1/agents", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ name: "test-agent" }),
  });
  const creation = await response.json<{
    agent: { id: string };
    agent_key: string;
  }>();
  agentId = creation.agent.id;
  agentKey = creation.agent_key;
});

describe("account-key storage", () => {
  it("stores only a one-way account-key digest", async () => {
    const account = await testEnv.DB.prepare("SELECT account_key_hash FROM accounts WHERE id = ?1")
      .bind("account_test")
      .first<{ account_key_hash: string }>();

    expect(account?.account_key_hash).toBe(await hashToken(TOKEN));
    expect(account?.account_key_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(account?.account_key_hash).not.toContain(TOKEN);
  });
});

describe("response security", () => {
  it("adds security headers to JSON responses", async () => {
    const response = await call("/health");

    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(response.headers.get("referrer-policy")).toBe("no-referrer");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
  });

  it("serves the website with browser-security headers", async () => {
    const response = await call("/");

    expect(response.status).toBe(200);
    expect(response.headers.get("content-security-policy")).toContain("default-src 'self'");
    expect(response.headers.get("strict-transport-security")).toContain("max-age=63072000");
    expect(response.headers.get("x-frame-options")).toBe("DENY");
    expect(await response.text()).toContain("HTML is the new markdown.");
  });
});

describe("device registration", () => {
  it("updates its owner and blocks a move to another account", async () => {
    const deviceID = "installation-test";
    const deviceToken = "cd".repeat(32);
    const registered = await call("/v1/devices", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        id: deviceID,
        apns_token: deviceToken,
        apns_environment: "development",
      }),
    });
    expect(registered.status).toBe(204);

    let device = await testEnv.DB.prepare(
      "SELECT account_id, apns_environment FROM devices WHERE id = ?1",
    )
      .bind(deviceID)
      .first<{ account_id: string; apns_environment: string }>();
    expect(device).toEqual({ account_id: "account_test", apns_environment: "development" });

    const updated = await call("/v1/devices", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        id: deviceID,
        apns_token: deviceToken,
        apns_environment: "production",
      }),
    });
    expect(updated.status).toBe(204);

    const secondToken = "ab_account_" + "move".repeat(8);
    await testEnv.DB.prepare(
      "INSERT INTO accounts (id, account_key_hash, created_at) VALUES (?1, ?2, ?3)",
    )
      .bind("account_device_move", await hashToken(secondToken), Math.floor(Date.now() / 1000))
      .run();
    const blocked = await call("/v1/devices", {
      method: "POST",
      headers: {
        authorization: `Bearer ${secondToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        id: deviceID,
        apns_token: deviceToken,
        apns_environment: "production",
      }),
    });
    expect(blocked.status).toBe(409);
    expect(await blocked.json()).toMatchObject({
      error: { code: "device_already_registered" },
    });

    device = await testEnv.DB.prepare(
      "SELECT account_id, apns_environment FROM devices WHERE id = ?1",
    )
      .bind(deviceID)
      .first<{ account_id: string; apns_environment: string }>();
    expect(device).toEqual({
      account_id: "account_test",
      apns_environment: "production",
    });

    const removed = await call(`/v1/devices/${deviceID}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(removed.status).toBe(204);

    const movedAfterRemoval = await call("/v1/devices", {
      method: "POST",
      headers: {
        authorization: `Bearer ${secondToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        id: deviceID,
        apns_token: deviceToken,
        apns_environment: "production",
      }),
    });
    expect(movedAfterRemoval.status).toBe(204);

    const finalRemoval = await call(`/v1/devices/${deviceID}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${secondToken}` },
    });
    expect(finalRemoval.status).toBe(204);
    expect(
      await testEnv.DB.prepare("SELECT id FROM devices WHERE id = ?1").bind(deviceID).first(),
    ).toBeNull();
  });
});

describe("account deletion", () => {
  it("deletes the account and all linked data", async () => {
    const accountToken = "ab_account_" + "delete".repeat(8);
    const accountID = "account_delete";
    const now = Math.floor(Date.now() / 1000);
    await testEnv.DB.batch([
      testEnv.DB.prepare(
        "INSERT INTO accounts (id, account_key_hash, created_at) VALUES (?1, ?2, ?3)",
      ).bind(accountID, await hashToken(accountToken), now),
      testEnv.DB.prepare(
        `INSERT INTO agents (
           id, account_id, name, api_key_hash, api_key_encrypted, api_key_hint, created_at
         ) VALUES ('agent_DELETE', ?1, 'delete-agent', 'delete-agent-hash', 'cipher', 'hint', ?2)`,
      ).bind(accountID, now),
      testEnv.DB.prepare(
        `INSERT INTO inboxes (id, account_id, name, local_part, created_at)
         VALUES ('inbox_DELETE', ?1, 'delete-inbox', 'delete-inbox', ?2)`,
      ).bind(accountID, now),
      testEnv.DB.prepare(
        `INSERT INTO cards (
           id, account_id, title, html, plain_text, source, created_at, metadata_json,
           agent_id, content_trust
         ) VALUES (
           'card_DELETE', ?1, 'Delete', '<p>Delete</p>', 'Delete', 'api', ?2, '{}',
           'agent_DELETE', 'trusted'
         )`,
      ).bind(accountID, now),
      testEnv.DB.prepare(
        `INSERT INTO devices (
           id, account_id, apns_token, apns_environment, created_at, last_seen_at
         ) VALUES ('device-delete', ?1, ?2, 'development', ?3, ?3)`,
      ).bind(accountID, "ef".repeat(32), now),
      testEnv.DB.prepare(
        "INSERT INTO account_push_state (account_id, last_sent_at) VALUES (?1, ?2)",
      ).bind(accountID, now),
    ]);
    await testEnv.DB.prepare(
      `INSERT INTO feedback (
         id, account_id, card_id, agent_id, comment, card_title, card_html,
         created_at, updated_at
       ) VALUES (
         'feedback_DELETE', ?1, 'card_DELETE', 'agent_DELETE', 'Delete', 'Delete',
         '<p>Delete</p>', ?2, ?2
       )`,
    )
      .bind(accountID, now)
      .run();

    const response = await call("/v1/account", {
      method: "DELETE",
      headers: { authorization: `Bearer ${accountToken}` },
    });
    expect(response.status).toBe(204);

    const remaining = await testEnv.DB.prepare(
      `SELECT
         (SELECT COUNT(*) FROM accounts WHERE id = ?1) +
         (SELECT COUNT(*) FROM agents WHERE account_id = ?1) +
         (SELECT COUNT(*) FROM inboxes WHERE account_id = ?1) +
         (SELECT COUNT(*) FROM cards WHERE account_id = ?1) +
         (SELECT COUNT(*) FROM card_changes WHERE account_id = ?1) +
         (SELECT COUNT(*) FROM devices WHERE account_id = ?1) +
         (SELECT COUNT(*) FROM account_push_state WHERE account_id = ?1) +
         (SELECT COUNT(*) FROM feedback WHERE account_id = ?1) AS count`,
    )
      .bind(accountID)
      .first<{ count: number }>();
    expect(remaining?.count).toBe(0);
  });
});

describe("account creation", () => {
  it("creates an empty account and returns its key one time", async () => {
    const response = await call("/v1/accounts", {
      method: "POST",
    });

    expect(response.status).toBe(201);
    const result = await response.json<{ account_key: string }>();
    expect(Object.keys(result)).toEqual(["account_key"]);
    expect(result.account_key).toMatch(/^ab_account_[A-Za-z0-9_-]{32,}$/);

    const stored = await testEnv.DB.prepare(
      "SELECT id, account_key_hash FROM accounts WHERE account_key_hash = ?1",
    )
      .bind(await hashToken(result.account_key))
      .first<{ id: string; account_key_hash: string }>();
    expect(stored?.id).toMatch(/^account_[A-Z0-9]+$/);
    expect(stored?.account_key_hash).not.toContain(result.account_key);
    const resources = await testEnv.DB.prepare(
      `SELECT
         (SELECT COUNT(*) FROM agents WHERE account_id = ?1) AS agent_count,
         (SELECT COUNT(*) FROM inboxes WHERE account_id = ?1) AS inbox_count`,
    )
      .bind(stored?.id)
      .first<{ agent_count: number; inbox_count: number }>();
    expect(resources).toEqual({ agent_count: 0, inbox_count: 0 });
  });
});

describe("card ingestion and synchronization", () => {
  it("rejects anonymous card creation", async () => {
    const response = await call("/v1/cards", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ html: "<p>Anonymous</p>" }),
    });
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ error: { code: "agent_key_required" } });
  });

  it("creates, preserves, syncs, clears, and restores an interactive card", async () => {
    const created = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
        "idempotency-key": "morning-1",
      },
      body: JSON.stringify({
        title: "Morning update",
        html: '<h2 onclick="alert(1)">Market</h2><script>alert(1)</script><p>Up &amp; right.</p>',
        expires_in: "24h",
        source_name: "spoofed-agent",
      }),
    });
    expect(created.status).toBe(201);
    const creation = await created.json<{ id: string; sequence: number }>();
    expect(creation.id).toMatch(/^card_[A-Z0-9]+$/);

    const sync = await call("/v1/sync?after=0", {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(sync.status).toBe(200);
    const firstSync = await sync.json<{
      cards: Array<{
        id: string;
        html: string;
        plain_text: string;
        cleared_at: string | null;
        agent_id: string | null;
        content_trust: string;
        source_name: string | null;
      }>;
      cursor: number;
    }>();
    expect(firstSync.cards).toHaveLength(1);
    expect(firstSync.cards[0]).toMatchObject({
      id: creation.id,
      plain_text: "Market Up & right.",
      cleared_at: null,
      agent_id: agentId,
      content_trust: "trusted",
      source_name: "test-agent",
    });
    expect(firstSync.cards[0].html).toContain("<script>alert(1)</script>");
    expect(firstSync.cards[0].html).toContain('onclick="alert(1)"');

    const cleared = await call(`/v1/cards/${creation.id}/clear`, {
      method: "POST",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(cleared.status).toBe(200);

    const changed = await call(`/v1/sync?after=${firstSync.cursor}`, {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    const secondSync = await changed.json<{
      cards: Array<{ id: string; cleared_at: string | null }>;
      cursor: number;
    }>();
    expect(secondSync.cards).toHaveLength(1);
    expect(secondSync.cards[0].id).toBe(creation.id);
    expect(secondSync.cards[0].cleared_at).not.toBeNull();
    expect(secondSync.cursor).toBeGreaterThan(firstSync.cursor);

    const restored = await call(`/v1/cards/${creation.id}/restore`, {
      method: "POST",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(restored.status).toBe(200);

    const restoredChange = await call(`/v1/sync?after=${secondSync.cursor}`, {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    const thirdSync = await restoredChange.json<{
      cards: Array<{ id: string; cleared_at: string | null }>;
      cursor: number;
    }>();
    expect(thirdSync.cards).toHaveLength(1);
    expect(thirdSync.cards[0]).toMatchObject({ id: creation.id, cleared_at: null });
    expect(thirdSync.cursor).toBeGreaterThan(secondSync.cursor);
  });

  it("returns the first card for a duplicate idempotency key", async () => {
    const headers = {
      authorization: `Bearer ${agentKey}`,
      "content-type": "application/json",
      "idempotency-key": "duplicate-1",
    };
    const first = await call("/v1/cards", {
      method: "POST",
      headers,
      body: JSON.stringify({ html: "<p>First</p>" }),
    });
    const second = await call("/v1/cards", {
      method: "POST",
      headers,
      body: JSON.stringify({ html: "<p>Second</p>" }),
    });
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect((await second.json<{ id: string }>()).id).toBe((await first.json<{ id: string }>()).id);

    const row = await testEnv.DB.prepare(
      "SELECT COUNT(*) AS count FROM cards WHERE agent_id = ?1 AND idempotency_key = ?2",
    )
      .bind(agentId, "duplicate-1")
      .first<{ count: number }>();
    expect(row?.count).toBe(1);
  });

  it("creates a scheduled card and starts its lifetime when it becomes visible", async () => {
    const showAt = new Date((Math.floor(Date.now() / 1000) + 7_200) * 1_000).toISOString();
    const response = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        title: "Thursday reminder",
        html: "<p>Review this later.</p>",
        show_at: showAt,
      }),
    });

    expect(response.status).toBe(201);
    const creation = await response.json<{
      id: string;
      show_at: string;
      expires_at: string;
    }>();
    expect(creation.show_at).toBe(showAt);
    expect(Date.parse(creation.expires_at) - Date.parse(creation.show_at)).toBe(86_400_000);

    const sync = await call("/v1/sync?after=0", {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    const result = await sync.json<{
      cards: Array<{ id: string; show_at: string | null }>;
    }>();
    expect(result.cards.find((card) => card.id === creation.id)?.show_at).toBe(showAt);

    const showNow = await call(`/v1/cards/${creation.id}/restore`, {
      method: "POST",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(showNow.status).toBe(200);
    expect(await showNow.json()).toMatchObject({ id: creation.id, show_at: null });

    const shownNow = await testEnv.DB.prepare("SELECT show_at FROM cards WHERE id = ?1")
      .bind(creation.id)
      .first<{ show_at: number | null }>();
    expect(shownNow?.show_at).toBeNull();

    const invalid = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ html: "<p>Too soon</p>", show_at: "Thursday" }),
    });
    expect(invalid.status).toBe(400);
    expect(await invalid.json()).toMatchObject({ error: { code: "invalid_schedule" } });

    const beforeRelativeRequest = Date.now();
    const relative = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
        "x-card-title": "Header schedule",
        "x-card-show-in": "2d",
        "x-card-expires-in": "3d",
      },
      body: JSON.stringify({ html: "<p>Header values</p>" }),
    });
    expect(relative.status).toBe(201);
    const relativeCreation = await relative.json<{
      show_at: string;
      expires_at: string;
    }>();
    expect(Date.parse(relativeCreation.show_at) - beforeRelativeRequest).toBeGreaterThanOrEqual(
      172_799_000,
    );
    expect(Date.parse(relativeCreation.show_at) - beforeRelativeRequest).toBeLessThanOrEqual(
      172_801_000,
    );
    expect(Date.parse(relativeCreation.expires_at) - Date.parse(relativeCreation.show_at)).toBe(
      259_200_000,
    );

    const storedRelative = await testEnv.DB.prepare("SELECT title FROM cards WHERE html = ?1")
      .bind("<p>Header values</p>")
      .first<{ title: string }>();
    expect(storedRelative?.title).toBe("Header schedule");
  });

  it("accepts direct HTML with remote assets and rejects invalid requests", async () => {
    const directExpiresAt = new Date((Math.floor(Date.now() / 1000) + 7_200) * 1_000).toISOString();
    const html = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "text/html",
        "x-card-title": "Direct HTML",
        "x-card-expires-at": directExpiresAt,
      },
      body: "<style>p { color: red; background: url(https://assets.example); }</style><p>Remote</p>",
    });
    expect(html.status).toBe(201);
    expect((await html.json<{ expires_at: string }>()).expires_at).toBe(directExpiresAt);

    const stored = await testEnv.DB.prepare("SELECT html FROM cards WHERE title = ?1")
      .bind("Direct HTML")
      .first<{ html: string }>();
    expect(stored?.html).toContain("url(https://assets.example)");

    const unauthorized = await call("/v1/sync?after=0");
    expect(unauthorized.status).toBe(401);

    const flexibleTtl = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ html: "<p>Flexible TTL</p>", expires_in: "2h 30m" }),
    });
    expect(flexibleTtl.status).toBe(201);
    const flexibleExpiration = await flexibleTtl.json<{ created_at: string; expires_at: string }>();
    expect(
      Date.parse(flexibleExpiration.expires_at) - Date.parse(flexibleExpiration.created_at),
    ).toBe(9_000_000);

    const invalidTtl = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ html: "<p>Bad TTL</p>", expires_in: "soon" }),
    });
    expect(invalidTtl.status).toBe(400);

    const invalidTitle = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ html: "<p>Bad title</p>", title: 42 }),
    });
    expect(invalidTitle.status).toBe(400);
  });

  it("rejects legacy username email and unknown inboxes", async () => {
    const raw = "Subject: Unknown\r\n\r\nHello";
    expect(await deliverEmail(raw, { to: "max@cards.example.com" })).toBe(
      "The card destination does not exist.",
    );
    expect(await deliverEmail(raw, { to: "unknown@agentboxes.cc" })).toBe(
      "The card destination does not exist.",
    );
  });
});

describe("agent feedback", () => {
  it("creates independent comments and lets only the card agent resolve them", async () => {
    const createdCard = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${agentKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        title: "Feedback card",
        html: "<main><h2>Original design</h2></main>",
      }),
    });
    const card = await createdCard.json<{ id: string }>();

    const first = await call(`/v1/cards/${card.id}/feedback`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ comment: "Make this card more concise." }),
    });
    expect(first.status).toBe(201);
    const firstResult = await first.json<{
      feedback: {
        id: string;
        card_id: string;
        agent_id: string;
        comment: string;
        card_html: string;
        resolved_at: string | null;
      };
    }>();
    expect(firstResult.feedback).toMatchObject({
      card_id: card.id,
      agent_id: agentId,
      comment: "Make this card more concise.",
      card_html: "<main><h2>Original design</h2></main>",
      resolved_at: null,
    });
    expect(firstResult.feedback.id).toMatch(/^feedback_[A-Z0-9]+$/);

    const second = await call(`/v1/cards/${card.id}/feedback`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ comment: "Include more interactive details." }),
    });
    expect(second.status).toBe(201);
    const secondResult = await second.json<{ feedback: { id: string } }>();

    const accountList = await call("/v1/feedback", {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(accountList.status).toBe(200);
    const accountFeedback = await accountList.json<{
      feedback: Array<{ id: string; agent_name: string }>;
    }>();
    expect(accountFeedback.feedback.map((item) => item.id)).toEqual(
      expect.arrayContaining([firstResult.feedback.id, secondResult.feedback.id]),
    );
    expect(
      accountFeedback.feedback.find((item) => item.id === firstResult.feedback.id)?.agent_name,
    ).toBe("test-agent");

    const agentList = await call("/v1/feedback?status=unresolved", {
      headers: { authorization: `Bearer ${agentKey}` },
    });
    expect(agentList.status).toBe(200);
    const agentFeedback = await agentList.json<{ feedback: Array<{ id: string }> }>();
    expect(agentFeedback.feedback.map((item) => item.id)).toEqual(
      expect.arrayContaining([firstResult.feedback.id, secondResult.feedback.id]),
    );

    const otherAgentResponse = await call("/v1/agents", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ name: "feedback-isolation-agent" }),
    });
    const otherAgent = await otherAgentResponse.json<{
      agent: { id: string };
      agent_key: string;
    }>();
    const otherList = await call("/v1/feedback", {
      headers: { authorization: `Bearer ${otherAgent.agent_key}` },
    });
    expect(await otherList.json()).toEqual({ feedback: [] });
    const otherResolve = await call(`/v1/feedback/${firstResult.feedback.id}/resolve`, {
      method: "POST",
      headers: { authorization: `Bearer ${otherAgent.agent_key}` },
    });
    expect(otherResolve.status).toBe(404);

    const edited = await call(`/v1/feedback/${firstResult.feedback.id}`, {
      method: "PATCH",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ comment: "Make the summary more concise." }),
    });
    expect(edited.status).toBe(200);
    expect(await edited.json()).toMatchObject({
      feedback: { comment: "Make the summary more concise." },
    });

    const resolved = await call(`/v1/feedback/${firstResult.feedback.id}/resolve`, {
      method: "POST",
      headers: { authorization: `Bearer ${agentKey}` },
    });
    expect(resolved.status).toBe(200);
    expect(
      (await resolved.json<{ feedback: { resolved_at: string | null } }>()).feedback.resolved_at,
    ).not.toBeNull();

    const unresolved = await call("/v1/feedback?status=unresolved", {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    const unresolvedFeedback = await unresolved.json<{ feedback: Array<{ id: string }> }>();
    expect(unresolvedFeedback.feedback.map((item) => item.id)).not.toContain(
      firstResult.feedback.id,
    );
    expect(unresolvedFeedback.feedback.map((item) => item.id)).toContain(secondResult.feedback.id);

    const removed = await call(`/v1/feedback/${secondResult.feedback.id}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(removed.status).toBe(204);
    await testEnv.DB.prepare("DELETE FROM agents WHERE id = ?1").bind(otherAgent.agent.id).run();
  });

  it("rejects feedback for a card without an agent", async () => {
    const now = Math.floor(Date.now() / 1_000);
    await testEnv.DB.prepare(
      `INSERT INTO cards (
         id, account_id, title, html, plain_text, source, source_name,
         created_at, expires_at, metadata_json, content_trust
       ) VALUES (?1, ?2, ?3, ?4, ?5, 'email', ?6, ?7, ?8, '{}', 'untrusted')`,
    )
      .bind(
        "card_FEEDBACKEMAIL",
        "account_test",
        "Email card",
        "<p>Email</p>",
        "Email",
        "sender@example.com",
        now,
        now + 3_600,
      )
      .run();

    const response = await call("/v1/cards/card_FEEDBACKEMAIL/feedback", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ comment: "This cannot reach an agent." }),
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: { code: "card_has_no_agent" } });
  });
});

describe("agent management", () => {
  it("stores an encrypted key and lists agent data without the clear key", async () => {
    const stored = await testEnv.DB.prepare(
      "SELECT api_key_hash, api_key_encrypted, api_key_hint FROM agents WHERE id = ?1",
    )
      .bind(agentId)
      .first<{ api_key_hash: string; api_key_encrypted: string; api_key_hint: string }>();
    expect(stored?.api_key_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(stored?.api_key_hash).not.toContain(agentKey);
    expect(stored?.api_key_encrypted).toMatch(/^v1\./);
    expect(stored?.api_key_encrypted).not.toContain(agentKey);
    expect(stored?.api_key_hint).toBe(agentKey.slice(-4));

    const response = await call("/v1/agents", {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text).not.toContain(agentKey);
    expect(JSON.parse(text)).toMatchObject({
      agents: [
        {
          id: agentId,
          name: "test-agent",
          key_hint: agentKey.slice(-4),
          revoked_at: null,
        },
      ],
    });

    const revealed = await call(`/v1/agents/${agentId}/key`, {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(revealed.status).toBe(200);
    expect(await revealed.json()).toEqual({ agent_key: agentKey });

    const renamed = await call(`/v1/agents/${agentId}`, {
      method: "PATCH",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ name: "Primary agent" }),
    });
    expect(renamed.status).toBe(200);
    expect(await renamed.json()).toMatchObject({ agent: { name: "Primary agent" } });

    const replaced = await call(`/v1/agents/${agentId}/key`, {
      method: "POST",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(replaced.status).toBe(200);
    const replacement = await replaced.json<{ agent_key: string }>();
    expect(replacement.agent_key).toMatch(/^ab_agent_[A-Za-z0-9_-]{32,}$/);
    expect(replacement.agent_key).not.toBe(agentKey);
    agentKey = replacement.agent_key;
  });

  it("revokes an agent, blocks its key, and downgrades its cards", async () => {
    const createdAgent = await call("/v1/agents", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ name: "temporary-agent" }),
    });
    const temporary = await createdAgent.json<{
      agent: { id: string };
      agent_key: string;
    }>();

    const createdCard = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${temporary.agent_key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ html: "<script>window.ready = true</script><p>Temporary</p>" }),
    });
    expect(createdCard.status).toBe(201);
    const card = await createdCard.json<{ id: string }>();

    const revoked = await call(`/v1/agents/${temporary.agent.id}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(revoked.status).toBe(204);

    const rejected = await call("/v1/cards", {
      method: "POST",
      headers: {
        authorization: `Bearer ${temporary.agent_key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ html: "<p>Rejected</p>" }),
    });
    expect(rejected.status).toBe(401);

    const storedCard = await testEnv.DB.prepare("SELECT content_trust FROM cards WHERE id = ?1")
      .bind(card.id)
      .first<{ content_trust: string }>();
    expect(storedCard?.content_trust).toBe("untrusted");
  });
});

describe("inbox management", () => {
  it("creates, lists, routes, and revokes a random email inbox", async () => {
    const create = await call("/v1/inboxes", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ name: "Newsletters" }),
    });
    expect(create.status).toBe(201);
    const created = await create.json<{
      inbox: { id: string; name: string; email_address: string; revoked_at: string | null };
    }>();
    expect(created.inbox).toMatchObject({ name: "Newsletters", revoked_at: null });
    expect(created.inbox.id).toMatch(/^inbox_[A-Z0-9]+$/);
    expect(created.inbox.email_address).toMatch(
      /^[a-z]+-[a-z]+-[a-z]+-[2-9a-hjkmnp-z]{6}@agentboxes\.cc$/,
    );

    const second = await call("/v1/inboxes", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ name: "Forms" }),
    });
    const secondInbox = await second.json<{ inbox: { email_address: string } }>();
    expect(secondInbox.inbox.email_address).not.toBe(created.inbox.email_address);

    const list = await call("/v1/inboxes", {
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(list.status).toBe(200);
    const listed = await list.json<{ inboxes: Array<{ id: string; email_address: string }> }>();
    expect(listed.inboxes).toContainEqual(
      expect.objectContaining({
        id: created.inbox.id,
        email_address: created.inbox.email_address,
      }),
    );

    const raw = [
      "From: newsletter@example.com",
      `To: ${created.inbox.email_address}`,
      "Subject: Monday brief",
      "Message-ID: <inbox-message-1@example.com>",
      "MIME-Version: 1.0",
      "Content-Type: text/html; charset=utf-8",
      "",
      '<script>window.ran = true</script><img src="https://example.com/pixel"><p>Brief</p>',
    ].join("\r\n");
    expect(
      await deliverEmail(raw, {
        to: created.inbox.email_address,
        messageId: "<inbox-message-1@example.com>",
      }),
    ).toBeNull();
    expect(
      await deliverEmail(raw, {
        to: created.inbox.email_address,
        messageId: "<inbox-message-1@example.com>",
      }),
    ).toBeNull();

    const card = await testEnv.DB.prepare(
      "SELECT title, content_trust, metadata_json FROM cards WHERE idempotency_key = ?1",
    )
      .bind("<inbox-message-1@example.com>")
      .first<{ title: string; content_trust: string; metadata_json: string }>();
    expect(card).toMatchObject({ title: "Monday brief", content_trust: "untrusted" });
    expect(JSON.parse(card?.metadata_json ?? "{}")).toMatchObject({
      inbox_id: created.inbox.id,
      inbox_name: "Newsletters",
    });

    const revoke = await call(`/v1/inboxes/${created.inbox.id}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(revoke.status).toBe(204);
    expect(
      await deliverEmail(raw, {
        to: created.inbox.email_address,
        messageId: "<inbox-message-2@example.com>",
      }),
    ).toBe("This inbox has been revoked.");

    const existingCard = await testEnv.DB.prepare(
      "SELECT COUNT(*) AS count FROM cards WHERE idempotency_key = ?1",
    )
      .bind("<inbox-message-1@example.com>")
      .first<{ count: number }>();
    expect(existingCard?.count).toBe(1);
  });
});
