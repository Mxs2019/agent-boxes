# Agent Box marketing site

This folder contains the static Agent Box marketing site. The Cloudflare Worker serves these files
and the account API from the same origin.

Run the local database migrations, then start the Worker:

```sh
npm run cloudflare:db:migrate:local
npm run cloudflare:dev
```

Open the local URL that Wrangler prints. The account form sends a request to `POST /v1/accounts`.

## Social share image

The file `public/og.png` is the image for link previews. The source file is `og-image.html`. To
make the image again after you change the source, run headless Chrome from this folder:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --screenshot=public/og.png --window-size=1200,630 --force-device-scale-factor=2 \
  --hide-scrollbars og-image.html
```
