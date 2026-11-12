# Product requirements (PRD)

## Product goal
A private, expandable, reliable home AI, accessible by a responsive website with secure login and optional voice. One consistent experience for devices, entertainment, network, automation, AI and server administration.

## Core user journeys
1. **First run:** local administrator completes protected setup; sets home timezone; registers AI provider later if desired.
2. **Dashboard:** authenticated user sees server health, integration health, rooms, devices, active music, automations and alerts.
3. **Room control:** user issues direct commands; actions are validated and show observed success/failure per device.
4. **Natural language:** user asks 'Turn off downstairs lights and play my playlist in the living room'; the AI proposes typed actions, which the Rust execution engine authorizes, performs and confirms.
5. **Automations:** deterministic local scheduler executes approved rules even if cloud AI is offline.
6. **Network:** administrator sees authorized LAN inventory, reachability history and diagnostics; any disruptive change requires explicit approval.
7. **Integrations:** administrator adds/configures/diagnoses/removes connectors without rewriting the core.
8. **Security:** user can see Yale lock status; unlock always requires explicit authorization plus stronger confirmation.

## Mandatory subsystems
- Native Rust modular monolith; SQLite migrations; normalized device capabilities; connector framework; event bus; async command engine; WebSocket state sync; auth/RBAC; auditing.
- Svelte/TypeScript web application: login, onboarding, AI chat, server status, devices, rooms, integrations, music, automations, network, logs/settings.
- AI adapters: at least one provider first, extensible to others; model context from registered capabilities; no fabricated state.
- Voice designed as optional bounded service, not a dependency for direct control.
- Native systemd service with health checks, reliable backups, secure updates and recovery instructions.

## Integration priorities
Loxone -> HEOS/Denon -> Spotify -> Apple Home interoperability -> Yale (exact model unknown) -> network/router connectors, while simulator, device registry and SDK come first. Order can change with real-device access.

## Non-goals in initial milestone
- Training a custom foundation model or running a large model on Core 2 Duo.
- Supporting every model from every vendor from day one.
- Directly reading an existing Apple Home database from Linux without an appropriate Apple-platform or supported pairing/bridge strategy.
- Exposing a general-purpose root shell to the AI or web UI.
- Unverified automatic unlocking, alarm disabling, or WAN configuration changes.

## Success metrics (measure, do not assume)
- One real, tested, authenticated web login and initial setup workflow.
- Verified direct device control in simulator, then proven with real hardware one connector at a time.
- Correct partial-failure reporting for multistep actions.
- Automations continue without external AI.
- System survives restart; logs and database persist; backup can restore in a test environment.
- Target idle core RSS 150–300 MB and low CPU if achievable; publish actual measurements.
