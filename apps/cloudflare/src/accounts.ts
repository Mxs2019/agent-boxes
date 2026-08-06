import { ulid } from "ulid";
import { hashToken } from "./auth";
import type { AccountRow } from "./types";

function generateAccountKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const encoded = btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
  return `ab_account_${encoded}`;
}

export async function createAccount(
  db: D1Database,
): Promise<{ account: AccountRow; accountKey: string }> {
  const accountKey = generateAccountKey();
  const account: AccountRow = {
    id: `account_${ulid()}`,
    account_key_hash: await hashToken(accountKey),
    created_at: Math.floor(Date.now() / 1000),
  };
  await db
    .prepare("INSERT INTO accounts (id, account_key_hash, created_at) VALUES (?1, ?2, ?3)")
    .bind(account.id, account.account_key_hash, account.created_at)
    .run();
  return { account, accountKey };
}

export async function deleteAccount(db: D1Database, accountId: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM feedback WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM card_changes WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM cards WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM account_push_state WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM devices WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM inboxes WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM agents WHERE account_id = ?1").bind(accountId),
    db.prepare("DELETE FROM accounts WHERE id = ?1").bind(accountId),
  ]);
}
