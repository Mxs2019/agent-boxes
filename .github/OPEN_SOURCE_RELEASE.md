# Open-source release settings

Complete these settings after you create the GitHub repository.

- Enable private vulnerability reporting.
- Enable secret scanning and push protection.
- Enable Dependabot alerts and security updates.
- Set the default workflow permission to read-only.
- Require approval for workflows from first-time external contributors.
- Add a `main` ruleset. Require the Repository checks and iOS build and tests jobs.
- Block branch deletion and force pushes for `main`.
- Run `npm run check` before the first push.

Do not publish a tag or release when one of these checks fails.
