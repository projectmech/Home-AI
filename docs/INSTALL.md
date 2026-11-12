# Installing, updating and recovering Home AI

Status, 2026-11-12: the scripts below are exercised by CI on a GitHub Ubuntu runner with real systemd (`scripts/test-install.sh`). They have **not** been run on Debian 13 or on the Mac mini. No release has been published yet, so the download path and the Sigstore signing step have never run.

The terminal is for installing and for emergencies. Everything else is meant to happen in the web interface; today that covers creating the administrator, signing in, device control, server metrics and the activity log. The rest of the setup wizard is not built yet.

## What the installer does and does not do
- Installs a **prebuilt, signed** release. It never compiles anything on the server.
- Refuses a bundle that is not proven to come from this repository's release workflow, and refuses a binary that does not run on this CPU.
- Creates a `home-ai` system account with no login and no password. Never creates a default administrator.
- Does not partition, format, or change boot or firmware settings.

| Path | Contents |
|---|---|
| `/opt/home-ai` | program and dashboard (root-owned, read-only to the service) |
| `/etc/home-ai/home-ai.env` | settings; no secrets |
| `/var/lib/home-ai` | database, HTTPS certificate and key, pre-update backups |
| `/etc/systemd/system/home-ai.service` | service definition |
| `/usr/local/bin/home-ai` | admin command (`sudo home-ai …`) |

## Install
The repository is private, so the server cannot download from GitHub anonymously. Two ways:

**A. Copy a bundle to the server (works without giving the server any GitHub access).**
On any computer, open the repository's Releases page in a browser and download two files from one release: `home-ai-<version>-linux-x86_64.tar.gz` and `home-ai-<version>-linux-x86_64.tar.gz.sigstore.json`. Copy them, and a copy of this repository, to the server, keeping the two files in the same folder. Then:
```
cd Home-AI
sudo ./install.sh --bundle /path/to/home-ai-<version>-linux-x86_64.tar.gz
```

**B. Let the installer download it** (NOT TESTED: it needs a published release).
```
git clone https://github.com/projectmech/Home-AI.git
cd Home-AI
sudo ./install.sh
```
With no arguments it installs the latest release (`--version v0.1.0` picks one). It first tries without signing in; because the repository is private, GitHub refuses, and it then asks for a GitHub token with read access to the repository. Use a fine-grained token limited to this repository with "Contents: read". The token is used for the download and not saved. `git clone` of a private repository needs its own credentials.

When it finishes it prints the dashboard address, the setup address, a one-time setup token, and the certificate fingerprint.

## The browser warning
The server makes its own certificate, so browsers warn on first visit. The connection is encrypted but **not verified** until you do one of these:
1. In the browser warning, view the certificate and compare its SHA-256 fingerprint with the one the installer printed (`sudo home-ai tls-fingerprint` shows it again). Continue only if identical.
2. Copy `/var/lib/home-ai/tls/cert.pem` to your devices and add it as a trusted certificate.

The certificate is valid for 820 days. Renewal is not implemented yet.

## First-time setup
Open `https://<server>:8443/setup`, enter the one-time token, choose the administrator username and a password of at least 12 characters, then sign in.
The token is valid for 60 minutes and works once. Five wrong attempts lock setup for a minute. Lost or expired:
```
sudo home-ai setup-token
```
That command refuses once an administrator exists. A restart, crash or power cut never reopens setup.

## Update and roll back
```
sudo ./update.sh --bundle /path/to/home-ai-<new-version>-linux-x86_64.tar.gz
sudo ./update.sh --rollback
```
`update.sh` verifies the bundle, stops the service, copies the database to `/var/lib/home-ai/backups/`, installs, starts and checks health. If the new version is not healthy it restores the previous program files and the database copy by itself. `--rollback` does the same on request; changes made after the update are lost, because the database returns to its pre-update copy.

That copy is on the same drive. It protects against a bad update, not against a failed drive. Off-device backups are not implemented yet.

Updating from the dashboard is not implemented yet.

## When the website is down
```
systemctl status home-ai                 # is it running?
journalctl -u home-ai -n 100 --no-pager  # recent log
sudo systemctl restart home-ai
sudo home-ai tls-fingerprint             # certificate still there?
sudo ./update.sh --rollback              # undo the last update
```
Restoring an older database copy by hand: stop the service, copy the chosen `home-ai.db` from `/var/lib/home-ai/backups/<folder>/` over `/var/lib/home-ai/home-ai.db`, delete `home-ai.db-wal` and `home-ai.db-shm` beside it, keep owner `home-ai`, start the service.

**Lost administrator password:** there is no recovery command yet. Until there is, the only way back in is restoring a database copy from when the password was known. This is a known gap (roadmap M1b).

## Uninstall
```
sudo ./uninstall.sh            # removes program and service, keeps data and settings
sudo ./uninstall.sh --purge    # also deletes database, certificate, backups, settings, account
```

## How releases are signed and checked
There is no signing key to create or keep. Details and limits: `docs/adr/0003-sigstore-keyless-release-signing.md`.

- Pushing a version tag such as `v0.1.0` runs the Release workflow. It builds for the Core 2 Duo baseline, signs the bundle with Sigstore keyless signing using the workflow's GitHub identity, verifies it, installs it once as a test, and publishes the bundle with its `.sigstore.json` evidence file.
- `install.sh` and `update.sh` accept a bundle only if that evidence proves it was signed by `.github/workflows/release.yml` of `projectmech/Home-AI` on a version tag, and the file is unaltered. A missing or invalid evidence file stops the install. There is no option to skip this.
- The first verification on a server downloads the verifier (cosign, about 140 MB, checksum-pinned) and needs internet access.
- Each release permanently records the repository name, workflow path, tag, commit SHA and bundle hash in Sigstore's public log, even though the repository is private. No code or contents are published.

To publish a release: set the version in `server/Cargo.toml`, commit, and push the matching tag.