# Security policy

## Report a vulnerability

Do not put vulnerability details in a public issue. Use the repository Security tab and select
**Report a vulnerability**. If private reporting is not available, ask the maintainer for a private
contact method. Do not include credentials or private data in that request.

Include the affected version, the affected component, reproduction steps, possible impact, and a
suggested fix when you have one.

## Security model

An Agent Box account has one `ab_account_…` key. There is no username or password. The service shows
the account key one time and stores only its SHA-256 hash. This key protects synchronization, card
actions, device registration, and management of agents and inboxes. The service cannot recover a
lost account key.

Each named agent has a separate `ab_agent_…` key for the MCP server and `POST /v1/cards`. D1 stores
its SHA-256 hash, an encrypted copy, and a four-character hint. The Worker uses AES-GCM and a
deployment secret to encrypt the copy. An account-key holder can view or replace an active agent
key. Revocation blocks new cards, MCP tool calls, and feedback access. It also changes that agent's
earlier cards to restricted mode during the next client sync.

The MCP endpoint accepts the agent key only in an `Authorization` header. It does not accept a key
in the URL. It rejects a cross-origin `Origin` header, uses no server session, and does not open an
SSE stream. Treat an MCP client configuration as a secret because it contains the agent key.

Each named email inbox has a random address. The address is visible and can be revoked, so it is a
routing value and not an account credential.

A device registration stays with its first account. Another account cannot move the registration.
The first account must remove the device before a different account can register it.

Authenticated agent cards can contain JavaScript and can make network requests. The iOS client runs
them in a nonpersistent web view without a native bridge. Email cards use restricted mode. This mode
blocks JavaScript, frames, forms, objects, and connections made by scripts. It permits HTTPS images.
A remote image can tell its server when the app loads it and can reveal network information such as
the user's IP address.

Each card can create a push notification that puts the card title and a short plain-text preview on
the lock screen. The notification contains a card identifier so that the app can open the correct
card. Users must control lock-screen preview access in the iOS notification settings when card
content is sensitive.

Deployers must enable rate limits and set `AGENT_KEY_ENCRYPTION_KEY` to 32 random bytes encoded as
base64url. Do not put account keys or agent keys in card HTML, source code, logs, issues, or
screenshots.
