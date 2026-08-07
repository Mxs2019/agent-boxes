# Agent Box Cloudflare service

This workspace contains the Agent Box Worker, D1 schema, API tests, email handler, and static-site
host.

## Local setup

Run these commands from the repository root:

```sh
npm ci
cp apps/cloudflare/.dev.vars.example apps/cloudflare/.dev.vars
npm run cloudflare:db:migrate:local
npm run cloudflare:dev
```

Replace the example encryption key in `.dev.vars` with 32 random bytes in base64url form. This file
is ignored by Git.

Create an account, then create an agent:

```sh
npm run cloudflare:account:create
AGENT_BOX_ACCOUNT_KEY='YOUR_ACCOUNT_KEY' npm run cloudflare:agent:create -- 'Research agent'
```

Create a card:

```sh
curl -X POST http://127.0.0.1:8787/v1/cards \
  -H 'Authorization: Bearer YOUR_AGENT_KEY' \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: morning-2026-08-03' \
  --data '{"title":"Things to review","html":"<h2>Today</h2><p>Review the onboarding flow.</p>","expires_in":"24h"}'
```

Use the account key for synchronization and resource management:

```sh
curl 'http://127.0.0.1:8787/v1/sync?after=0' \
  -H 'Authorization: Bearer YOUR_ACCOUNT_KEY'

curl -X POST http://127.0.0.1:8787/v1/inboxes \
  -H 'Authorization: Bearer YOUR_ACCOUNT_KEY' \
  -H 'Content-Type: application/json' \
  --data '{"name":"Newsletters"}'
```

See [the shared contract](../../packages/contracts/CARD_CONTRACT.md) for all endpoints and fields.

## Email ingestion

The Worker accepts mail for `*@agentboxes.cc`. It sends mail to a card only when the random
address matches an active inbox in D1. A revoked address stays reserved and rejects new mail.
Attachments are ignored. Email cards always use restricted mode.

Cloudflare DNS must manage `agentboxes.cc`. Enable Email Routing and deploy the Worker. The
`addresses` value in `wrangler.jsonc` creates the catch-all Worker route.

## Checks and deployment

```sh
npm run check --workspace @agent-box/cloudflare
npm run cloudflare:db:migrate:remote
npm run cloudflare:deploy
```

Before the first production deployment, create these queues from `apps/cloudflare`:

```sh
npx wrangler queues create agent-box-card-updates
npx wrangler queues create agent-box-card-updates-dlq
```

Create the `agent-box` D1 database and put its identifier in `wrangler.jsonc`. Set
`AGENT_KEY_ENCRYPTION_KEY` as a Worker secret. The secret must decode to 32 bytes. Do not put it in
`vars` or commit it.

The committed D1 identifier is an all-zero placeholder. Replace it in your local working tree before
deployment. Do not commit a real deployment identifier.

## APNs background updates

The card-update queue combines new-card events by account. Its consumer sends a visible APNs alert
to each current device, sets the current active-card badge count, and asks iOS to refresh the cards
in the background. APNs keeps one collapsed notification for the app for up to one hour. The iOS app
downloads all changes after its local cursor.

The visible alert shows the card title and a short plain-text preview on the lock screen. A grouped
alert uses generic text. Users must control lock-screen preview access in the iOS notification
settings when card content is sensitive.

Enable Push Notifications for the `cc.agentboxes` App ID. Create an APNs authentication key in
the Apple Developer portal. Record its Key ID and the Apple Team ID. Download its `.p8` private key
and store it safely. Apple permits one download of this file.

New Apple APNs keys are limited to one environment. Create one topic-specific key for the Sandbox
environment and one topic-specific key for the Production environment. Limit both keys to
`cc.agentboxes`.

Set these APNs values as Worker secrets from `apps/cloudflare`:

```sh
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_DEVELOPMENT_KEY_ID
npx wrangler secret put APNS_DEVELOPMENT_PRIVATE_KEY
npx wrangler secret put APNS_PRODUCTION_KEY_ID
npx wrangler secret put APNS_PRODUCTION_PRIVATE_KEY
```

Paste the complete matching `.p8` file, including its BEGIN and END lines, for each private-key
secret. The APNs topic is the `APNS_TOPIC` value in `wrangler.jsonc`.

Apply the remote D1 migration before deployment. The migration adds the APNs environment to each
device. Deploy the Worker after the queues, secrets, and migration are ready.
