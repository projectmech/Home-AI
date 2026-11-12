# ADR 0003 — Sigstore keyless release signing

Date: 2026-11-12. Status: accepted; **the signing half has not run yet** (it runs only when a version tag is pushed). Supersedes "Authenticity of releases" in ADR 0002 and the Ed25519 key described in the first version of docs/INSTALL.md.

## Requirement (user, 2026-11-12)
No permanent private signing key to manage. Sign in GitHub Actions with GitHub OIDC. Verify provenance and integrity before install and update. Accept only releases from the authorized repository and its release workflow. Reject missing or invalid evidence. Never disable verification or fall back to unsigned downloads. Work on Debian and a Core 2 Duo.

## Decision
- **Signing:** the Release workflow runs `cosign sign-blob` on the release tarball. Sigstore's certificate authority (Fulcio) issues a certificate valid for minutes to the workflow run's GitHub OIDC identity, the signature is recorded in Sigstore's public transparency log (Rekor), and the private key is discarded. Output: `<bundle>.tar.gz.sigstore.json`, published beside the tarball.
- **Verification:** `install.sh` and `update.sh` call `verify_bundle` in `packaging/lib.sh`, which runs `cosign verify-blob` and requires:
  - certificate identity matching `^https://github\.com/projectmech/Home-AI/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$`
  - OIDC issuer `https://token.actions.githubusercontent.com`
  - a signature over exactly this file (so integrity is covered; the separate `SHA256SUMS` file is gone).
  A signature made by another repository, another workflow file, or a branch build does not match and is rejected.
- **No bypass:** `--insecure-skip-signature` is removed. A bundle without its `.sigstore.json` is refused.
- **The verifier is pinned:** cosign v3.1.4, `cosign-linux-amd64`, SHA-256 `424e2c97…bbfa` (the digest GitHub shows on that release). The scripts download it once to `/usr/local/lib/home-ai/`, check the hash, and refuse to continue on mismatch. A system-installed cosign is deliberately not used.
- **The release proves itself before publishing:** `scripts/release-sign.sh` signs, verifies with the same function the installer uses, and checks that an altered file, a file with no evidence, and a foreign identity are all rejected. The workflow then installs the signed bundle with `sudo ./install.sh` (production path) before creating the release.

## Why not GitHub's own artifact attestations
`actions/attest-build-provenance` is the more integrated option, but for **private** repositories GitHub offers artifact attestations only on the Enterprise Cloud plan. On other plans it is limited to public repositories. Calling cosign directly has no such restriction: any repository, any plan, as long as the workflow may request an OIDC token (`permissions: id-token: write`).
*This is my understanding of GitHub's terms as of my knowledge; check the current GitHub documentation before relying on it.*

## What keeping the repository private does and does not hide
The repository's contents stay private. But keyless signing uses Sigstore's **public** infrastructure, so each release permanently publishes, in the certificate and the transparency log:
- the repository name `projectmech/Home-AI` and owner,
- the workflow path `.github/workflows/release.yml`,
- the tag (for example `refs/tags/v0.1.0`) and the commit SHA,
- the time, and the SHA-256 of the release tarball.
No source code, no file names beyond the workflow, no release contents. This cannot be undone once a release is signed. Avoiding it would need a private Sigstore deployment or a managed key, which is what the requirement rules out.

## Limits and risks
- **Trust shifts, it does not vanish.** Instead of guarding a key, you rely on: your GitHub account and repository settings (anyone who can push a `v*` tag or edit `release.yml` on a tag can make an accepted release), GitHub's OIDC issuer, and Sigstore's public services. Protect tags and the workflow file (branch/tag protection, 2FA on the account).
- **Renames break verification on purpose.** Renaming the repository, its owner, or the workflow file changes the signing identity. Update `RELEASE_IDENTITY_REGEXP` first; already-installed servers verify with the script version they have.
- **Internet is needed to verify.** cosign fetches Sigstore's trust root, and the first run downloads cosign itself (about 140 MB). An air-gapped install is not supported.
- **Core 2 Duo:** cosign is a static Go binary built for baseline amd64, so it should run. **Not tested** on that CPU. If it does not run, the scripts stop rather than skip verification.
- **cosign CLI drift:** flags are written for v3.1.4, pinned. I could not run cosign locally; the first tag push is the first execution of the signing step.
- **Web-initiated updates** do not exist yet. When built they must call the same verification.

## The CI test hook
`verify_bundle` has one alternative path, used only by `scripts/test-install.sh`: when both `CI=true` and `HOME_AI_TEST_PUBKEY` are set, it verifies an Ed25519 signature made with a key generated during that test run. It exists so install, update and rollback can be tested on every push without writing to the public transparency log. It is still a signature check, it prints a warning, and `sudo` does not pass those variables unless given explicitly. Someone who can set root's environment on the server can already do anything, so this adds no new capability, but it is a second code path and is recorded here for that reason.
