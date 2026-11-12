# Full prompts — JARVIS / Mac mini home AI

This folder consolidates the development prompts from our conversation into reusable Markdown documents for Claude Code.

## Read order and conflict precedence

1. `01-JARVIS-MASTER-PROMPT.md` — original product scope and detailed integration requirements.
2. `02-MAC-MINI-RUST-DASHBOARD-MASTER.md` — 2010 Mac mini design, independent Rust core, secure login and administration dashboard.
3. `03-256GB-DEPLOYMENT-AND-PERFORMANCE.md` — latest storage capacity, unknown SSD/HDD, Debian boot, deployment and measured performance requirements.

**Priority for conflicting instructions: 03 > 02 > 01**. Newer instructions override older technology choices, but the earlier functional requirements remain in scope. In particular: Rust replaces the original TypeScript/Node.js core proposal; native systemd deployment replaces mandatory Docker; the 256 GB drive's media type is *unknown* and must be detected.

`04-CLAUDE-CODE-KICKOFF.md` is a ready-to-paste first message. The `../docs/` folder contains the structured implementation specifications, including roadmap, test plan, references and open questions.

These prompt files are carefully consolidated and organized from the conversation; they preserve requirements and examples but are **not guaranteed to be character-for-character transcripts**. No passwords or API tokens are included.

## Addendum
`05-VOICE-PERSONALITY-HUMOR.md` (2026-11-12) adds mandatory voice, personality, humor and memory requirements. It extends the voice sections of 01 and 02. Prompt 03's hardware and performance limits still apply to it.

`06-GITHUB-INSTALL-AND-WEB-SETUP.md` (2026-11-12) adds mandatory installation, web setup wizard, update and recovery requirements, and asks for them before the integrations.
