# Agent Box marketing site

This folder contains the static Agent Box marketing site. The Cloudflare Worker serves these files
and the account API from the same origin.

Run the local database migrations, then start the Worker:

```sh
npm run cloudflare:db:migrate:local
npm run cloudflare:dev
```

Open the local URL that Wrangler prints. The account form sends a request to `POST /v1/accounts`.
