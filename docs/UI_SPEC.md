# UI/UX specification

## Visual language
Clean Apple-inspired responsive admin UI: dark/light themes, restrained grayscale, subtle frosted surfaces, generous spacing, readable typography, no neon/glow. Mobile-first components with keyboard, screen-reader and touch accessibility. Keep motion light on legacy hardware (frontend runs in user's modern browser; backend still minimal).

## Required routes
- `/login`: identity and password, error feedback, optional second factor.
- `/setup`: protected first-run bootstrap; disabled after admin creation.
- `/`: home overview and alerts.
- `/rooms`: organized devices and scenes.
- `/devices`: registry, alias, capability details, online status, direct controls.
- `/integrations`: add/configure/test/remove connectors, credential status.
- `/ai`: chat, request execution cards, streaming action progress.
- `/music`: players, groups, playback and sources.
- `/network`: router/LAN status, diagnostic tools, history.
- `/automations`: editor, logs and enable/disable.
- `/server`: uptime, CPU, RAM, disk health/type, logs, restart/backup/update.
- `/settings`: users, sessions, permissions, AI provider, retention, timezone.

## Core interaction rules
- Login is genuinely enforced by Rust API (not frontend only).
- WebSocket actions display queued/running/confirmed/failed/unknown, per action.
- Show 'not supported' or 'not available' rather than fabricated state.
- Distinguish simulated vs real devices visually.
- Risks like unlock and network changes require confirmation and step-up authentication.
- Display genuine hardware metrics; unknown disk type stays 'Unknown'.
- Never surface secrets in logs or browser API payloads.

## Example user journeys
1. After login, server health and devices render; connector status changes without page reload.
2. Direct light command shows result and observed device state.
3. AI requests three device actions; two succeed and one fails; UI reports precise outcome.
4. Admin views performance chart and switches ECO/BALANCED/PERFORMANCE within safe limits.
