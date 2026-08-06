PRAGMA foreign_keys = ON;

CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  account_key_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

CREATE TABLE agents (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  name TEXT NOT NULL,
  api_key_hash TEXT NOT NULL UNIQUE,
  api_key_encrypted TEXT NOT NULL,
  api_key_hint TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER,
  revoked_at INTEGER,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE inboxes (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  name TEXT NOT NULL,
  local_part TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  revoked_at INTEGER,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE cards (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  account_id TEXT NOT NULL,
  title TEXT,
  html TEXT NOT NULL,
  plain_text TEXT NOT NULL,
  source TEXT NOT NULL,
  source_name TEXT,
  created_at INTEGER NOT NULL,
  show_at INTEGER,
  expires_at INTEGER,
  cleared_at INTEGER,
  idempotency_key TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  agent_id TEXT,
  content_trust TEXT NOT NULL DEFAULT 'untrusted'
    CHECK (content_trust IN ('trusted', 'untrusted')),
  FOREIGN KEY (account_id) REFERENCES accounts(id),
  FOREIGN KEY (agent_id) REFERENCES agents(id)
);

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  apns_token TEXT,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE card_changes (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id TEXT NOT NULL,
  card_id TEXT NOT NULL,
  changed_at INTEGER NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id),
  FOREIGN KEY (card_id) REFERENCES cards(id)
);

CREATE UNIQUE INDEX agents_account_active_name
  ON agents(account_id, name)
  WHERE revoked_at IS NULL;
CREATE INDEX agents_account_created_at ON agents(account_id, created_at DESC);
CREATE INDEX inboxes_account_created_at ON inboxes(account_id, created_at DESC);
CREATE UNIQUE INDEX cards_agent_idempotency_key
  ON cards(agent_id, idempotency_key)
  WHERE agent_id IS NOT NULL AND idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX cards_email_idempotency_key
  ON cards(account_id, idempotency_key)
  WHERE source = 'email' AND idempotency_key IS NOT NULL;
CREATE INDEX cards_account_created_at ON cards(account_id, created_at DESC);
CREATE INDEX cards_account_active ON cards(account_id, cleared_at, expires_at, sequence);
CREATE INDEX cards_account_show_at ON cards(account_id, show_at, sequence);
CREATE INDEX cards_agent_id ON cards(agent_id);
CREATE INDEX devices_account_id ON devices(account_id);
CREATE INDEX card_changes_account_sequence ON card_changes(account_id, sequence);

CREATE TRIGGER cards_record_insert
AFTER INSERT ON cards
BEGIN
  INSERT INTO card_changes (account_id, card_id, changed_at)
  VALUES (NEW.account_id, NEW.id, unixepoch());
END;

CREATE TRIGGER cards_record_update
AFTER UPDATE ON cards
BEGIN
  INSERT INTO card_changes (account_id, card_id, changed_at)
  VALUES (NEW.account_id, NEW.id, unixepoch());
END;
