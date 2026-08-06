# Contributing

Thank you for contributing to Agent Box.

## Before you submit a change

Run these commands from the repository root:

```sh
npm ci
npm run check
```

The check scans the files that Git can publish for common credentials and private local data.

Do not commit:

- Account keys, agent keys, API tokens, private keys, or signing files.
- `.env`, `.dev.vars`, personal `.npmrc` files, or local configuration files. The root `.npmrc` is
  public project configuration. Do not put registry credentials in it.
- Cloudflare local state or SQLite databases.
- Xcode user data, build output, or local home-directory paths.
- Real card content or personal data in tests and screenshots.

Use synthetic data in fixtures. Before you submit a Cloudflare configuration change, remove any
account-specific identifiers that Wrangler added during deployment.

Report security problems through the process in [SECURITY.md](SECURITY.md).

All contributions use the repository [MIT License](LICENSE). Read the
[code of conduct](CODE_OF_CONDUCT.md) before you take part in project discussions.
