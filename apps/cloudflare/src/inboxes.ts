import { ulid } from "ulid";
import { HttpError } from "./errors";
import type { AccountRow, Inbox, InboxRow } from "./types";

const WORDS = [
  "acorn",
  "alpaca",
  "apple",
  "apricot",
  "badger",
  "basil",
  "beaver",
  "berry",
  "biscuit",
  "blueberry",
  "breeze",
  "button",
  "cactus",
  "carrot",
  "cashew",
  "cedar",
  "cherry",
  "cloud",
  "coconut",
  "comet",
  "cookie",
  "cucumber",
  "daisy",
  "dolphin",
  "dumpling",
  "fern",
  "fig",
  "finch",
  "firefly",
  "fox",
  "ginger",
  "grape",
  "hazel",
  "honey",
  "jelly",
  "kiwi",
  "lemon",
  "lilac",
  "lotus",
  "mango",
  "maple",
  "marble",
  "melon",
  "mint",
  "moon",
  "mouse",
  "muffin",
  "nectar",
  "noodle",
  "olive",
  "otter",
  "papaya",
  "peach",
  "pebble",
  "pepper",
  "pickle",
  "pigeon",
  "plum",
  "poppy",
  "pumpkin",
  "rabbit",
  "radish",
  "rain",
  "saliva",
  "sparrow",
  "sprout",
  "squash",
  "star",
  "tangerine",
  "thistle",
  "toast",
  "tomato",
  "tulip",
  "walnut",
  "willow",
  "wombat",
] as const;

function randomWord(): string {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);
  return WORDS[values[0] % WORDS.length];
}

export function generateInboxLocalPart(): string {
  const alphabet = "23456789abcdefghjkmnpqrstuvwxyz";
  const values = new Uint8Array(6);
  crypto.getRandomValues(values);
  const suffix = Array.from(values, (value) => alphabet[value % alphabet.length]).join("");
  return `${randomWord()}-${randomWord()}-${randomWord()}-${suffix}`;
}

function date(value: number | null): string | null {
  return value === null ? null : new Date(value * 1000).toISOString();
}

export function toInbox(row: InboxRow, domain: string): Inbox {
  return {
    id: row.id,
    name: row.name,
    email_address: `${row.local_part}@${domain}`,
    created_at: new Date(row.created_at * 1000).toISOString(),
    revoked_at: date(row.revoked_at),
  };
}

export async function createInbox(
  db: D1Database,
  account: AccountRow,
  rawName: unknown,
  domain: string,
): Promise<Inbox> {
  if (typeof rawName !== "string") {
    throw new HttpError(400, "invalid_inbox_name", "Inbox name must be a string.");
  }
  const name = rawName.trim();
  if (!name || name.length > 80) {
    throw new HttpError(400, "invalid_inbox_name", "Inbox name must contain 1 to 80 characters.");
  }

  const activeCount = await db
    .prepare("SELECT COUNT(*) AS count FROM inboxes WHERE account_id = ?1 AND revoked_at IS NULL")
    .bind(account.id)
    .first<{ count: number }>();
  if ((activeCount?.count ?? 0) >= 100) {
    throw new HttpError(
      409,
      "inbox_limit_reached",
      "Revoke an old inbox before you create another one.",
    );
  }

  const createdAt = Math.floor(Date.now() / 1000);
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      const row = await db
        .prepare(
          `INSERT INTO inboxes (id, account_id, name, local_part, created_at, revoked_at)
           VALUES (?1, ?2, ?3, ?4, ?5, NULL)
           RETURNING *`,
        )
        .bind(`inbox_${ulid()}`, account.id, name, generateInboxLocalPart(), createdAt)
        .first<InboxRow>();
      if (!row) throw new Error("D1 did not return the created inbox.");
      return toInbox(row, domain);
    } catch (error) {
      const message = error instanceof Error ? error.message.toLowerCase() : "";
      if (!message.includes("unique") || !message.includes("local_part")) throw error;
    }
  }

  throw new HttpError(503, "inbox_address_unavailable", "A new inbox address is not available.");
}

export async function listInboxes(
  db: D1Database,
  account: AccountRow,
  domain: string,
): Promise<Inbox[]> {
  const rows = await db
    .prepare(
      `SELECT id, account_id, name, local_part, created_at, revoked_at
       FROM inboxes
       WHERE account_id = ?1
       ORDER BY revoked_at IS NOT NULL ASC, created_at DESC
       LIMIT 200`,
    )
    .bind(account.id)
    .all<InboxRow>();
  return rows.results.map((row) => toInbox(row, domain));
}

async function findInbox(db: D1Database, account: AccountRow, inboxId: string): Promise<InboxRow> {
  const inbox = await db
    .prepare(
      `SELECT id, account_id, name, local_part, created_at, revoked_at
       FROM inboxes WHERE id = ?1 AND account_id = ?2`,
    )
    .bind(inboxId, account.id)
    .first<InboxRow>();
  if (!inbox) throw new HttpError(404, "inbox_not_found", "The inbox does not exist.");
  return inbox;
}

export async function renameInbox(
  db: D1Database,
  account: AccountRow,
  inboxId: string,
  rawName: unknown,
  domain: string,
): Promise<Inbox> {
  const inbox = await findInbox(db, account, inboxId);
  if (inbox.revoked_at !== null) {
    throw new HttpError(410, "inbox_revoked", "The inbox was revoked.");
  }
  if (typeof rawName !== "string") {
    throw new HttpError(400, "invalid_inbox_name", "Inbox name must be a string.");
  }
  const name = rawName.trim();
  if (!name || name.length > 80) {
    throw new HttpError(400, "invalid_inbox_name", "Inbox name must contain 1 to 80 characters.");
  }
  const row = await db
    .prepare("UPDATE inboxes SET name = ?1 WHERE id = ?2 AND account_id = ?3 RETURNING *")
    .bind(name, inbox.id, account.id)
    .first<InboxRow>();
  if (!row) throw new Error("D1 did not return the updated inbox.");
  return toInbox(row, domain);
}

export async function revokeInbox(
  db: D1Database,
  account: AccountRow,
  inboxId: string,
): Promise<void> {
  const inbox = await findInbox(db, account, inboxId);
  if (inbox.revoked_at !== null) return;

  await db
    .prepare("UPDATE inboxes SET revoked_at = ?1 WHERE id = ?2 AND account_id = ?3")
    .bind(Math.floor(Date.now() / 1000), inboxId, account.id)
    .run();
}
