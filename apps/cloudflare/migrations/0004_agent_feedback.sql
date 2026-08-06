PRAGMA foreign_keys = ON;

CREATE TABLE feedback (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  card_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  comment TEXT NOT NULL,
  card_title TEXT,
  card_html TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  resolved_at INTEGER,
  FOREIGN KEY (account_id) REFERENCES accounts(id),
  FOREIGN KEY (card_id) REFERENCES cards(id),
  FOREIGN KEY (agent_id) REFERENCES agents(id)
);

CREATE INDEX feedback_account_status_created
  ON feedback(account_id, resolved_at, created_at);
CREATE INDEX feedback_agent_status_created
  ON feedback(agent_id, resolved_at, created_at);
CREATE INDEX feedback_card_created
  ON feedback(card_id, created_at);
