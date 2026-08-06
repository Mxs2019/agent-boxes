CREATE TABLE IF NOT EXISTS account_push_state (
  account_id TEXT PRIMARY KEY,
  last_sent_at INTEGER NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);
