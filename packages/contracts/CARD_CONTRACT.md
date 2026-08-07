# Agent Box contract

This contract applies to the Cloudflare service and all Agent Box clients.

## Credentials

- An account key starts with `ab_account_`. It is shown one time and cannot be recovered.
- An agent key starts with `ab_agent_`. An account-key holder can view, replace, or revoke it.
- A client uses the account key. An agent uses only its own agent key.
- Requests use `Authorization: Bearer {key}`.

## Create an account

`POST /v1/accounts` has no request body and needs no authorization.

```json
{ "account_key": "ab_account_…" }
```

The response contains only the one-time account key. A new account has no visible agents and no
inboxes. The server adds five non-expiring onboarding cards in deck order. These cards use the
`system` source and have `metadata.onboarding` set to `1`.

The server also creates one hidden system agent named "Agent Box" and attaches the onboarding
cards to it. This lets the user send feedback on onboarding cards. The system agent does not
appear in `GET /v1/agents`, and the agent-management endpoints cannot change or revoke it. No
client holds its key.

`POST /v1/onboarding/reset` needs the account key. It clears active onboarding cards and adds a new
ordered set of five onboarding cards. It does not delete old cards from History.

`DELETE /v1/account` needs the account key. It permanently deletes the account and all cards,
feedback, agents, inboxes, device registrations, push state, and change records.

## Manage agents

All agent-management requests need the account key. A name must contain 1 to 80 characters.

- `POST /v1/agents` with `{ "name": "Research agent" }` creates an agent and returns `agent`,
  `agent_key`, `mcp_url`, and `post_url`.
- `GET /v1/agents` lists agents without clear keys.
- `PATCH /v1/agents/{agent_id}` with `{ "name": "New name" }` changes the name.
- `GET /v1/agents/{agent_id}/key` returns the clear key for an active agent.
- `POST /v1/agents/{agent_id}/key` replaces the key and returns the new clear key.
- `DELETE /v1/agents/{agent_id}` revokes the agent.

## Agent MCP server

`/mcp` is a stateless MCP Streamable HTTP endpoint. It uses MCP protocol version `2025-11-25` and
also accepts `2025-06-18` and `2025-03-26`. Every request needs the agent key as an
`Authorization: Bearer {agent_key}` header. The endpoint does not put credentials in its URL.

The server has these tools:

- `send_card` creates a card. Its fields match the JSON fields for `POST /v1/cards`. The tool adds
  `idempotency_key` as an input field instead of an HTTP header.
- `list_feedback` lists `all`, `unresolved`, or `resolved` feedback for cards from this agent. The
  default is `unresolved`.
- `resolve_feedback` resolves one feedback item that belongs to this agent.

The endpoint uses JSON-RPC 2.0. It returns JSON responses and does not create server sessions or
SSE streams. `GET /mcp` and `DELETE /mcp` return `405 Method Not Allowed`. A client must send both
`application/json` and `text/event-stream` in the `Accept` header on POST requests. After
initialization, a client must send its negotiated version in the `MCP-Protocol-Version` header.

## Manage email inboxes

All inbox-management requests need the account key. A name must contain 1 to 80 characters.

- `POST /v1/inboxes` with `{ "name": "Newsletters" }` creates a random address.
- `GET /v1/inboxes` lists inboxes and their addresses.
- `PATCH /v1/inboxes/{inbox_id}` changes the name.
- `DELETE /v1/inboxes/{inbox_id}` revokes the address.

The inbox domain is `agentboxes.cc` in production. Email cards always use restricted mode.

## Create a card

`POST /v1/cards` is the HTTP fallback for clients that do not support MCP. It needs an agent key.
The server gets `source_name`, `agent_id`, and `content_trust` from the authenticated agent. Request
content cannot override these values.

```json
{
  "title": "Things to review",
  "html": "<h2>Today</h2><p>Review the new onboarding flow.</p>",
  "show_in": "2d",
  "expires_in": "24h",
  "metadata": {}
}
```

Use `Content-Type: application/json` or send direct HTML with `Content-Type: text/html`. Optional
headers are `X-Card-Title`, `X-Card-Show-At`, `X-Card-Show-In`, `X-Card-Expires-In`, and
`X-Card-Expires-At`. A header takes priority over its JSON field. `X-Card-TTL` is an alias for
`X-Card-Expires-In`.

Send `Idempotency-Key` when a request can be retried. Its maximum length is 255 characters. The
maximum body size is 500 KB, the title limit is 300 characters, and metadata can contain at most
32 KB of JSON.

The default lifetime is `24h`. Use an ISO 8601 value for `show_at` or `expires_at`. Use a positive
relative duration for `show_in` or `expires_in`. A duration can use seconds, ISO 8601 notation, or
units such as `45m`, `2h 30m`, `10 days`, `3w`, and `P1DT12H`. Use `never` for no expiration.

## Card data

```json
{
  "id": "card_01K…",
  "account_id": "account_01K…",
  "sequence": 1042,
  "title": "Morning market update",
  "html": "<h2>Market update</h2><p>…</p>",
  "plain_text": "Market update…",
  "created_at": "2026-08-03T10:00:00.000Z",
  "show_at": null,
  "expires_at": "2026-08-04T10:00:00.000Z",
  "cleared_at": null,
  "source": "api",
  "source_name": "Research agent",
  "agent_id": "agent_01K…",
  "content_trust": "trusted",
  "metadata": {}
}
```

`source` is `api`, `email`, or `system`. The server uses `system` only for Agent Box service cards.

All dates use UTC ISO 8601 strings. `sequence` is the stable card creation order. The sync cursor is
a separate global change sequence.

## Synchronization and actions

These requests need the account key:

- `GET /v1/sync?after={cursor}&limit={limit}` returns changed cards, a cursor, `has_more`, and
  `server_time`. The default limit is 200 and the maximum is 500.
- `POST /v1/cards/{card_id}/clear` clears a card.
- `POST /v1/cards/{card_id}/restore` restores a card. It removes a past expiration time, but it keeps
  a future expiration time.
- `POST /v1/devices` registers an installation and its APNs environment:
  `{ "id": "installation-id", "apns_token": "token", "apns_environment": "production" }`.
- `DELETE /v1/devices/{installation_id}` removes the installation.

`apns_environment` is `development` or `production`. The server accepts a missing value from an old
client and uses `production`.

A device identifier can belong to only one account. A different account gets a `409` response. The
current account must remove the device before a different account can register it.

A scheduled card is hidden until `show_at`. An active card is due, not cleared, and not expired. A
clear or expiration action does not delete the card. The active deck sorts by `sequence` from low
to high. History sorts by `created_at` from high to low.

## Agent feedback

Feedback is available only for a card that an agent created. Each feedback item is independent. A
user can add more than one feedback item to the same card. A comment must contain 1 to 5,000
characters.

The following requests need the account key:

- `POST /v1/cards/{card_id}/feedback` with `{ "comment": "Make this card more concise." }` creates
  a feedback item.
- `GET /v1/feedback?status=all` lists all feedback for the account.
- `PATCH /v1/feedback/{feedback_id}` with `{ "comment": "New comment" }` changes the comment.
- `DELETE /v1/feedback/{feedback_id}` deletes the feedback item.

The agent can use its own key for these requests:

- `GET /v1/feedback?status=unresolved` lists only feedback for cards that this agent created.
- `POST /v1/feedback/{feedback_id}/resolve` resolves one feedback item that belongs to this agent.

`status` can be `all`, `unresolved`, or `resolved`. The default is `all`. Lists use chronological
order from oldest to newest. An agent cannot read or resolve feedback for another agent.

```json
{
  "id": "feedback_01K…",
  "card_id": "card_01K…",
  "agent_id": "agent_01K…",
  "agent_name": "Research agent",
  "comment": "Make this card more concise.",
  "card_title": "Morning market update",
  "card_html": "<h2>Market update</h2><p>…</p>",
  "created_at": "2026-08-06T10:00:00.000Z",
  "updated_at": "2026-08-06T10:00:00.000Z",
  "resolved_at": null
}
```

The service copies the card title and HTML into the feedback item when the user creates it. This
snapshot gives the agent the exact card context even if the agent did not keep the original card.
