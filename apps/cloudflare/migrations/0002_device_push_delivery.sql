ALTER TABLE devices
ADD COLUMN apns_environment TEXT NOT NULL DEFAULT 'production'
  CHECK (apns_environment IN ('development', 'production'));

CREATE INDEX devices_account_environment
  ON devices(account_id, apns_environment);
