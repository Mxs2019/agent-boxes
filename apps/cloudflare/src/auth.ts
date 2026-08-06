import { HttpError } from "./errors";
import type { AccountRow, AgentRow } from "./types";

export async function hashToken(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function bearerToken(request: Request, code: string, message: string): string {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) throw new HttpError(401, code, message);
  const token = authorization.slice(7).trim();
  if (!token) throw new HttpError(401, code, message);
  return token;
}

export async function authenticateAccount(request: Request, db: D1Database): Promise<AccountRow> {
  const key = bearerToken(request, "account_key_required", "An account key is required.");
  if (!/^ab_account_[A-Za-z0-9_-]{32,}$/.test(key) || key.length > 200) {
    throw new HttpError(401, "invalid_account_key", "The account key is not valid.");
  }

  const account = await db
    .prepare("SELECT id, account_key_hash, created_at FROM accounts WHERE account_key_hash = ?1")
    .bind(await hashToken(key))
    .first<AccountRow>();
  if (!account) throw new HttpError(401, "invalid_account_key", "The account key is not valid.");
  return account;
}

export async function authenticateAgent(
  request: Request,
  db: D1Database,
): Promise<{ account: AccountRow; agent: AgentRow }> {
  const key = bearerToken(request, "agent_key_required", "An agent key is required.");
  if (!/^ab_agent_[A-Za-z0-9_-]{32,}$/.test(key) || key.length > 200) {
    throw new HttpError(401, "invalid_agent_key", "The agent key is not valid.");
  }

  const row = await db
    .prepare(
      `SELECT
         agents.id, agents.account_id, agents.name, agents.api_key_hash,
         agents.api_key_encrypted, agents.api_key_hint, agents.created_at,
         agents.last_used_at, agents.revoked_at,
         accounts.account_key_hash, accounts.created_at AS account_created_at
       FROM agents
       JOIN accounts ON accounts.id = agents.account_id
       WHERE agents.api_key_hash = ?1 AND agents.revoked_at IS NULL`,
    )
    .bind(await hashToken(key))
    .first<AgentRow & { account_key_hash: string; account_created_at: number }>();

  if (!row) {
    throw new HttpError(401, "invalid_agent_key", "The agent key is not valid or was revoked.");
  }

  const now = Math.floor(Date.now() / 1000);
  await db.prepare("UPDATE agents SET last_used_at = ?1 WHERE id = ?2").bind(now, row.id).run();
  row.last_used_at = now;
  return {
    account: {
      id: row.account_id,
      account_key_hash: row.account_key_hash,
      created_at: row.account_created_at,
    },
    agent: row,
  };
}

export async function authenticateFeedbackReader(
  request: Request,
  db: D1Database,
): Promise<{ account: AccountRow; agent: AgentRow | null }> {
  const key = bearerToken(
    request,
    "feedback_key_required",
    "An account key or agent key is required.",
  );
  if (key.startsWith("ab_account_")) {
    return { account: await authenticateAccount(request, db), agent: null };
  }
  if (key.startsWith("ab_agent_")) {
    return authenticateAgent(request, db);
  }
  throw new HttpError(401, "invalid_feedback_key", "The account key or agent key is not valid.");
}
