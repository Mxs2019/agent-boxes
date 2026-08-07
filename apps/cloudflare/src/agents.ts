import { ulid } from "ulid";
import { hashToken } from "./auth";
import { decryptAgentKey, encryptAgentKey } from "./encryption";
import { HttpError } from "./errors";
import type { AccountRow, Agent, AgentRow } from "./types";

function date(value: number | null): string | null {
  return value === null ? null : new Date(value * 1000).toISOString();
}

export function toAgent(row: AgentRow): Agent {
  return {
    id: row.id,
    name: row.name,
    key_hint: row.api_key_hint,
    created_at: new Date(row.created_at * 1000).toISOString(),
    last_used_at: date(row.last_used_at),
    revoked_at: date(row.revoked_at),
  };
}

export function generateAgentKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const encoded = btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `ab_agent_${encoded}`;
}

function cleanName(rawName: unknown): string {
  if (typeof rawName !== "string") {
    throw new HttpError(400, "invalid_agent_name", "Agent name must be a string.");
  }
  const name = rawName.trim();
  if (!name || name.length > 80) {
    throw new HttpError(400, "invalid_agent_name", "Agent name must contain 1 to 80 characters.");
  }
  return name;
}

async function findAgent(db: D1Database, account: AccountRow, agentId: string): Promise<AgentRow> {
  const agent = await db
    .prepare(
      `SELECT id, account_id, name, api_key_hash, api_key_encrypted, api_key_hint, is_system,
              created_at, last_used_at, revoked_at
       FROM agents WHERE id = ?1 AND account_id = ?2 AND is_system = 0`,
    )
    .bind(agentId, account.id)
    .first<AgentRow>();
  if (!agent) throw new HttpError(404, "agent_not_found", "The agent does not exist.");
  return agent;
}

export async function createAgent(
  db: D1Database,
  account: AccountRow,
  rawName: unknown,
  encryptionSecret: string,
): Promise<{ agent: Agent; agentKey: string }> {
  const name = cleanName(rawName);
  const activeCount = await db
    .prepare(
      "SELECT COUNT(*) AS count FROM agents WHERE account_id = ?1 AND revoked_at IS NULL AND is_system = 0",
    )
    .bind(account.id)
    .first<{ count: number }>();
  if ((activeCount?.count ?? 0) >= 100) {
    throw new HttpError(
      409,
      "agent_limit_reached",
      "Revoke an old agent before you create another one.",
    );
  }

  const id = `agent_${ulid()}`;
  const agentKey = generateAgentKey();
  const keyHash = await hashToken(agentKey);
  const encryptedKey = await encryptAgentKey(agentKey, encryptionSecret, id);
  const createdAt = Math.floor(Date.now() / 1000);

  try {
    const row = await db
      .prepare(
        `INSERT INTO agents (
          id, account_id, name, api_key_hash, api_key_encrypted, api_key_hint,
          created_at, last_used_at, revoked_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, NULL)
        RETURNING *`,
      )
      .bind(id, account.id, name, keyHash, encryptedKey, agentKey.slice(-4), createdAt)
      .first<AgentRow>();
    if (!row) throw new Error("D1 did not return the created agent.");
    return { agent: toAgent(row), agentKey };
  } catch (error) {
    const existing = await db
      .prepare("SELECT id FROM agents WHERE account_id = ?1 AND name = ?2 AND revoked_at IS NULL")
      .bind(account.id, name)
      .first<{ id: string }>();
    if (existing) {
      throw new HttpError(409, "agent_name_exists", "An active agent already uses this name.");
    }
    throw error;
  }
}

const SYSTEM_AGENT_NAMES = ["Agent Box", "Agent Box (system)"] as const;

/**
 * Finds or creates the account's hidden system agent. Onboarding cards attach
 * to it so the feedback flow works before the user creates a real agent. Its
 * key is generated and discarded — nothing can authenticate as this agent.
 */
export async function ensureSystemAgent(
  db: D1Database,
  account: AccountRow,
  encryptionSecret: string,
): Promise<string> {
  const existing = await db
    .prepare(
      `SELECT id FROM agents
       WHERE account_id = ?1 AND is_system = 1 AND revoked_at IS NULL
       ORDER BY created_at ASC LIMIT 1`,
    )
    .bind(account.id)
    .first<{ id: string }>();
  if (existing) return existing.id;

  const createdAt = Math.floor(Date.now() / 1000);
  let lastError: unknown = null;
  for (const name of SYSTEM_AGENT_NAMES) {
    const id = `agent_${ulid()}`;
    const agentKey = generateAgentKey();
    try {
      const row = await db
        .prepare(
          `INSERT INTO agents (
            id, account_id, name, api_key_hash, api_key_encrypted, api_key_hint,
            is_system, created_at, last_used_at, revoked_at
          ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1, ?7, NULL, NULL)
          RETURNING id`,
        )
        .bind(
          id,
          account.id,
          name,
          await hashToken(agentKey),
          await encryptAgentKey(agentKey, encryptionSecret, id),
          agentKey.slice(-4),
          createdAt,
        )
        .first<{ id: string }>();
      if (row) return row.id;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError instanceof Error
    ? lastError
    : new Error("The system agent could not be created.");
}

export async function listAgents(db: D1Database, account: AccountRow): Promise<Agent[]> {
  const rows = await db
    .prepare(
      `SELECT id, account_id, name, api_key_hash, api_key_encrypted, api_key_hint, is_system,
              created_at, last_used_at, revoked_at
       FROM agents
       WHERE account_id = ?1 AND is_system = 0
       ORDER BY revoked_at IS NOT NULL ASC, created_at DESC
       LIMIT 200`,
    )
    .bind(account.id)
    .all<AgentRow>();
  return rows.results.map(toAgent);
}

export async function revealAgentKey(
  db: D1Database,
  account: AccountRow,
  agentId: string,
  encryptionSecret: string,
): Promise<string> {
  const agent = await findAgent(db, account, agentId);
  if (agent.revoked_at !== null) {
    throw new HttpError(410, "agent_revoked", "The agent was revoked.");
  }
  return decryptAgentKey(agent.api_key_encrypted, encryptionSecret, agent.id);
}

export async function replaceAgentKey(
  db: D1Database,
  account: AccountRow,
  agentId: string,
  encryptionSecret: string,
): Promise<string> {
  const agent = await findAgent(db, account, agentId);
  if (agent.revoked_at !== null) {
    throw new HttpError(410, "agent_revoked", "The agent was revoked.");
  }
  const agentKey = generateAgentKey();
  await db
    .prepare(
      `UPDATE agents
       SET api_key_hash = ?1, api_key_encrypted = ?2, api_key_hint = ?3, last_used_at = NULL
       WHERE id = ?4 AND account_id = ?5`,
    )
    .bind(
      await hashToken(agentKey),
      await encryptAgentKey(agentKey, encryptionSecret, agent.id),
      agentKey.slice(-4),
      agent.id,
      account.id,
    )
    .run();
  return agentKey;
}

export async function renameAgent(
  db: D1Database,
  account: AccountRow,
  agentId: string,
  rawName: unknown,
): Promise<Agent> {
  const agent = await findAgent(db, account, agentId);
  if (agent.revoked_at !== null) {
    throw new HttpError(410, "agent_revoked", "The agent was revoked.");
  }
  const name = cleanName(rawName);
  try {
    const row = await db
      .prepare("UPDATE agents SET name = ?1 WHERE id = ?2 AND account_id = ?3 RETURNING *")
      .bind(name, agent.id, account.id)
      .first<AgentRow>();
    if (!row) throw new Error("D1 did not return the updated agent.");
    return toAgent(row);
  } catch (error) {
    const existing = await db
      .prepare("SELECT id FROM agents WHERE account_id = ?1 AND name = ?2 AND revoked_at IS NULL")
      .bind(account.id, name)
      .first<{ id: string }>();
    if (existing) {
      throw new HttpError(409, "agent_name_exists", "An active agent already uses this name.");
    }
    throw error;
  }
}

export async function revokeAgent(
  db: D1Database,
  account: AccountRow,
  agentId: string,
): Promise<void> {
  const agent = await findAgent(db, account, agentId);
  if (agent.revoked_at !== null) return;
  const revokedAt = Math.floor(Date.now() / 1000);
  await db.batch([
    db
      .prepare("UPDATE agents SET revoked_at = ?1 WHERE id = ?2 AND account_id = ?3")
      .bind(revokedAt, agentId, account.id),
    db
      .prepare(
        `UPDATE cards SET content_trust = 'untrusted'
         WHERE agent_id = ?1 AND account_id = ?2 AND content_trust = 'trusted'`,
      )
      .bind(agentId, account.id),
  ]);
}
