import { ulid } from "ulid";
import { HttpError } from "./errors";
import { resolveExpiration } from "./expiration";
import { makePlainText, validateCardHtml } from "./html";
import { resolveShowAt } from "./scheduling";
import type { Card, CardRow, CardSource, AccountRow } from "./types";

export interface CreateCardInput {
  title?: string;
  html: string;
  showAt?: string;
  showIn?: string | number;
  expiresIn?: string | number;
  expiresAt?: string;
  source: CardSource;
  sourceName?: string;
  agentId?: string;
  idempotencyKey?: string;
  metadata?: Record<string, unknown>;
}

export interface CreateCardResult {
  card: Card;
  created: boolean;
}

function optionalText(value: unknown, field: string, maxLength: number): string | null {
  if (value === undefined) return null;
  if (typeof value !== "string") {
    throw new HttpError(400, `invalid_${field}`, `${field} must be a string.`);
  }
  if (!value.trim()) return null;
  const clean = value.trim();
  if (clean.length > maxLength) {
    throw new HttpError(
      400,
      `invalid_${field}`,
      `${field} must be at most ${maxLength} characters.`,
    );
  }
  return clean;
}

export function toCard(row: CardRow): Card {
  let metadata: Record<string, unknown> = {};
  try {
    metadata = JSON.parse(row.metadata_json) as Record<string, unknown>;
  } catch {
    metadata = {};
  }

  return {
    id: row.id,
    account_id: row.account_id,
    sequence: row.sequence,
    title: row.title,
    html: row.html,
    plain_text: row.plain_text,
    created_at: new Date(row.created_at * 1000).toISOString(),
    show_at: row.show_at === null ? null : new Date(row.show_at * 1000).toISOString(),
    expires_at: row.expires_at === null ? null : new Date(row.expires_at * 1000).toISOString(),
    cleared_at: row.cleared_at === null ? null : new Date(row.cleared_at * 1000).toISOString(),
    source: row.source,
    source_name: row.source_name,
    agent_id: row.agent_id,
    content_trust: row.content_trust,
    metadata,
  };
}

async function findIdempotentCard(
  db: D1Database,
  account: AccountRow,
  source: CardSource,
  agentId: string | undefined,
  idempotencyKey: string,
): Promise<CardRow | null> {
  if (source === "api" && agentId) {
    return db
      .prepare("SELECT * FROM cards WHERE agent_id = ?1 AND idempotency_key = ?2")
      .bind(agentId, idempotencyKey)
      .first<CardRow>();
  }
  if (source === "email") {
    return db
      .prepare(
        "SELECT * FROM cards WHERE account_id = ?1 AND source = 'email' AND idempotency_key = ?2",
      )
      .bind(account.id, idempotencyKey)
      .first<CardRow>();
  }
  return null;
}

export async function createCard(
  db: D1Database,
  account: AccountRow,
  input: CreateCardInput,
): Promise<CreateCardResult> {
  const title = optionalText(input.title, "title", 300);
  const sourceName = optionalText(input.sourceName, "source_name", 300);
  const idempotencyKey = optionalText(input.idempotencyKey, "idempotency_key", 255);
  const agentId = input.source === "api" ? input.agentId : undefined;
  if (input.source === "api" && !agentId) {
    throw new HttpError(500, "missing_agent", "API cards require an authenticated agent.");
  }
  const contentTrust = agentId ? "trusted" : "untrusted";

  if (idempotencyKey) {
    const existing = await findIdempotentCard(db, account, input.source, agentId, idempotencyKey);
    if (existing) return { card: toCard(existing), created: false };
  }

  const html = validateCardHtml(input.html);
  const plainText = (await makePlainText(html)) || title || "Interactive card";

  const metadata = input.metadata ?? {};
  if (!metadata || Array.isArray(metadata) || typeof metadata !== "object") {
    throw new HttpError(400, "invalid_metadata", "metadata must be a JSON object.");
  }
  const metadataJson = JSON.stringify(metadata);
  if (new TextEncoder().encode(metadataJson).byteLength > 32 * 1024) {
    throw new HttpError(400, "invalid_metadata", "metadata must be at most 32 KB.");
  }

  const createdAt = Math.floor(Date.now() / 1000);
  const showAt = resolveShowAt(createdAt, input.showAt, input.showIn);
  const expiresAt = resolveExpiration(showAt ?? createdAt, input.expiresIn, input.expiresAt);
  const id = `card_${ulid()}`;

  try {
    const inserted = await db
      .prepare(
        `INSERT INTO cards (
          id, account_id, title, html, plain_text, source, source_name,
          created_at, show_at, expires_at, cleared_at, idempotency_key, metadata_json,
          agent_id, content_trust
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, NULL, ?11, ?12, ?13, ?14)
        RETURNING *`,
      )
      .bind(
        id,
        account.id,
        title,
        html,
        plainText,
        input.source,
        sourceName,
        createdAt,
        showAt,
        expiresAt,
        idempotencyKey,
        metadataJson,
        agentId ?? null,
        contentTrust,
      )
      .first<CardRow>();
    if (!inserted) throw new Error("D1 did not return the inserted card.");
    return { card: toCard(inserted), created: true };
  } catch (error) {
    if (!idempotencyKey) throw error;
    const existing = await findIdempotentCard(db, account, input.source, agentId, idempotencyKey);
    if (existing) return { card: toCard(existing), created: false };
    throw error;
  }
}
