# Agent Box

Agent Box is a simple delivery service for people and software agents. An account has one private
account key. It has no username or password. Clients use the account key to synchronize cards and
to manage named agents and named email inboxes.

Each agent has a separate key for the MCP server and the `POST /v1/cards` HTTP fallback. Each inbox
has a random address on `agentboxes.cc`. See [SECURITY.md](SECURITY.md) before you deploy the
service.

## Repository structure

The repository is an npm-workspace monorepo. Each deployable product lives in `apps/`. Shared
definitions live in `packages/`.

```text
apps/
  cloudflare/  The service: API, email routing, and static-site host
  mobile/      Native iOS client
  web/         Marketing site and web account creation
packages/
  contracts/   Shared product and API contracts
```

### apps/cloudflare — the service

One Cloudflare Worker serves the whole backend: the HTTP API on `api.agentboxes.cc`, inbound
email routing for named inboxes, and the static marketing site on `agentboxes.cc`. Route handlers
live in `src/`, the D1 schema lives in `migrations/`, and Vitest tests live in `test/`. The
`scripts/` folder holds local helpers that create accounts and agents.

### apps/mobile — the iOS client

A native Swift app in `AgentBox.xcodeproj`. It signs in with the account key, synchronizes cards
through `GET /v1/sync`, stores them for offline reading, and shows the swipeable deck and
history. Unit tests live in `AgentBoxTests/` and UI tests live in `AgentBoxUITests/`.

### apps/web — the marketing site

A static site with plain HTML, CSS, and JavaScript and no build step. Its deployable files are in
`public/`. The Cloudflare Worker serves them as static assets. It explains the product and creates accounts against
`POST /v1/accounts`.

### packages/contracts

The product and API contract in `CARD_CONTRACT.md`. The service and all clients follow this
document. Change the contract first when you change behavior that crosses the API.

## Local setup

```sh
npm ci
npm run cloudflare:db:migrate:local
npm run cloudflare:dev
```

Use npm 12.0.2. The repository uses exact dependency versions and accepts a dependency release
only after seven days.

In another terminal, create an account and an agent:

```sh
npm run cloudflare:account:create
AGENT_BOX_ACCOUNT_KEY='YOUR_ACCOUNT_KEY' npm run cloudflare:agent:create -- 'Research agent'
```

Connect an MCP client to `http://127.0.0.1:8787/mcp` with Streamable HTTP. Send the created agent
key in the `Authorization: Bearer {agent_key}` header. The MCP server gives the agent tools to send
cards, list feedback, and resolve feedback.

Run all checks:

```sh
npm run check
```

The root check scans public files, tests the Cloudflare service and website, checks formatting,
builds the iOS client, and runs the iOS tests.

Agent Box uses the [MIT License](LICENSE). Read [CONTRIBUTING.md](CONTRIBUTING.md) before you submit a
change. Read [PRIVACY.md](PRIVACY.md) for data use and deletion. Third-party license and asset
information is in [NOTICE.md](NOTICE.md).
