ALTER TABLE agents ADD COLUMN is_system INTEGER NOT NULL DEFAULT 0;

CREATE INDEX agents_account_system ON agents(account_id, is_system);
