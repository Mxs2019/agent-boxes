export const CARD_SOURCES = ["api", "email"] as const;

export type CardSource = (typeof CARD_SOURCES)[number];

export const CONTENT_TRUST_LEVELS = ["trusted", "untrusted"] as const;

export type ContentTrust = (typeof CONTENT_TRUST_LEVELS)[number];

export interface Card {
  id: string;
  account_id: string;
  sequence: number;
  title: string | null;
  html: string;
  plain_text: string;
  created_at: string;
  show_at: string | null;
  expires_at: string | null;
  cleared_at: string | null;
  source: CardSource;
  source_name: string | null;
  agent_id: string | null;
  content_trust: ContentTrust;
  metadata: Record<string, unknown>;
}

export interface CreateCardJson {
  title?: string;
  html: string;
  show_at?: string;
  show_in?: string | number;
  expires_in?: string | number;
  expires_at?: string;
  metadata?: Record<string, unknown>;
}

export interface SyncResponse {
  cards: Card[];
  cursor: number;
  has_more: boolean;
  server_time: string;
}

export interface DeviceRegistration {
  id: string;
  apns_token: string;
  apns_environment?: ApnsEnvironment;
}

export type ApnsEnvironment = "development" | "production";

export interface DeviceRow {
  id: string;
  account_id: string;
  apns_token: string;
  apns_environment: ApnsEnvironment;
  created_at: number;
  last_seen_at: number;
}

export interface CardUpdateMessage {
  account_id: string;
  card_id?: string;
  source_name?: string | null;
  title?: string | null;
}

export interface CardRow {
  sequence: number;
  id: string;
  account_id: string;
  title: string | null;
  html: string;
  plain_text: string;
  source: CardSource;
  source_name: string | null;
  agent_id: string | null;
  content_trust: ContentTrust;
  created_at: number;
  show_at: number | null;
  expires_at: number | null;
  cleared_at: number | null;
  idempotency_key: string | null;
  metadata_json: string;
}

export interface Agent {
  id: string;
  name: string;
  key_hint: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

export interface AgentRow {
  id: string;
  account_id: string;
  name: string;
  api_key_hash: string;
  api_key_encrypted: string;
  api_key_hint: string;
  created_at: number;
  last_used_at: number | null;
  revoked_at: number | null;
}

export interface Inbox {
  id: string;
  name: string;
  email_address: string;
  created_at: string;
  revoked_at: string | null;
}

export interface InboxRow {
  id: string;
  account_id: string;
  name: string;
  local_part: string;
  created_at: number;
  revoked_at: number | null;
}

export interface AccountRow {
  id: string;
  account_key_hash: string;
  created_at: number;
}

export interface Feedback {
  id: string;
  card_id: string;
  agent_id: string;
  agent_name: string;
  comment: string;
  card_title: string | null;
  card_html: string;
  created_at: string;
  updated_at: string;
  resolved_at: string | null;
}

export interface FeedbackRow {
  id: string;
  account_id: string;
  card_id: string;
  agent_id: string;
  agent_name: string;
  comment: string;
  card_title: string | null;
  card_html: string;
  created_at: number;
  updated_at: number;
  resolved_at: number | null;
}
