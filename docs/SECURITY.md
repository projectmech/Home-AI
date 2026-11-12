# Security requirements and threat model

## Assets / threats
Protect home access (locks), network configuration, API keys, session cookies, personal device inventory, location and occupancy patterns. Threats include stolen credentials, CSRF/XSS, prompt injection via device names/media metadata, LAN attackers, compromised connectors, leaked logs, unsafe backup/update tooling and insecure bootstrap.

## Must-have controls
- Single-use local bootstrap with no default admin password.
- Argon2id password hashing; secure rate limits; configurable MFA/passkeys; RBAC/ABAC checked on the backend.
- HTTPS for authenticated sessions; HttpOnly secure cookies, CSRF protection where appropriate and secure origin handling.
- Secrets never in repo, logs or frontend; encrypted/restricted secrets store and redacted `.env.example`.
- Structured capability/risk policy that validates every AI/device command. Unlock requires step-up authorization and confirmation; voice identity alone is insufficient.
- Prompt injection isolation: external text (web, metadata, device labels, Spotify tracks, connector responses) is data, not instructions.
- Connectors need minimal permissions and bounded network destinations; third-party execution in isolated subprocesses if implemented.
- Backups encrypted as needed and tested on separate storage; update packages checked for authenticity; no arbitrary installer scripts.
- No unauthenticated API, public WAN port forwarding or root web terminal by default.

## Approval gates
Hardware erase, OS install, changes to locks/alarms, network configuration, backup deletion, privilege changes and production secret rotation require clear admin approval. Simulators must not have production privileges.

## Testing
Auth bypass, CSRF, XSS, session fixation, escalation, connector spoofing/failure, prompt injection, unsafe URL/shell execution, secret leaks, audit integrity, restore and recovery.
