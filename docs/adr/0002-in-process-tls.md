# ADR 0002 — HTTPS in the binary, setup token from a local command, private repository

Date: 2026-11-12. Status: accepted. Supersedes the TLS and first-run rows of ADR 0001. Driven by `prompts/06`.

## HTTPS
- The binary terminates TLS itself (`axum-server` + `rustls` with the `ring` provider). No reverse proxy is required. `ring` was chosen over `aws-lc-rs` because it needs no cmake at build time and selects CPU features at run time, which suits the Core 2 Duo baseline. **Unverified on the real CPU until the Mac mini smoke test.**
- `APP_TLS=self-signed` makes the server create, once, an ECDSA P-256 certificate in `<data dir>/tls/` (key file mode 600), valid 820 days, for the names in `APP_TLS_NAMES` plus `localhost` and `127.0.0.1`. An existing certificate is never replaced, so the fingerprint is stable across restarts.
- `home-ai tls-fingerprint` prints the SHA-256 fingerprint. The installer will print it so the user can compare it with what the browser shows, or install `cert.pem` as trusted on their devices. Until they do one of those, the connection is encrypted but **not authenticated**, and the product must say so.
- `APP_TLS=off` (the default, for development) serves plain HTTP and is accepted **only on loopback**. The server still refuses plaintext on any network address.
- Not done: renewal before the 820 days run out, a user-supplied certificate, HSTS, HTTP→HTTPS redirect.

## Setup token
- Issued only by `home-ai setup-token`, which needs write access to the database file. Stored as a SHA-256 hash with a one-hour expiry; five wrong guesses lock setup for a minute; deleted in the transaction that creates the administrator.
- The server never creates or prints a token. A restart, crash or power cut cannot reopen or re-key setup.
- Lost or expired token: run the command again. It refuses once an administrator exists.
- Not done: recovering access when the only administrator's password is lost. That needs a separate, deliberate local command and is part of M1b recovery work.

## Repository stays private (user decision, 2026-11-12)
- The three-line install from `prompts/06` §3 cannot work unauthenticated against a private repository.
- Consequence for the installer: it must not assume it can download from GitHub anonymously. Planned shape: `install.sh` installs from a **release bundle file** the user supplies (downloaded in a browser on any machine and copied to the server), and can alternatively fetch it using a read-only GitHub token the user provides at the prompt. The token is never written to disk by the installer.
- Web-initiated updates have the same constraint and need a stored read-only credential or an uploaded bundle. To be designed with the updater.
- If the repository is made public later, anonymous download becomes the default path and the rest still works.

## Authenticity of releases (still open)
Checksums prove integrity, not origin. A signing key whose public half ships in the repository is required before `install.sh` or the updater may call a download "verified". Candidates: minisign, or GitHub artifact attestations. Decide when the release workflow is written.
