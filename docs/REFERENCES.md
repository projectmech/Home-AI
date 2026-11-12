# Authoritative sources (recheck versions when implementing)

Use official product/API docs as primary sources; treat them as **references**, not permission to assume every feature is available on the user's particular hardware.

- Claude Code project instructions: https://code.claude.com/docs/en/memory
- Claude Code best practices: https://code.claude.com/docs/en/best-practices
- Claude Code project settings: https://code.claude.com/docs/en/settings
- Claude Code skills: https://code.claude.com/docs/en/skills
- Loxone Miniserver API: https://www.loxone.com/enen/kb/api/
- Loxone WebSocket/connection PDF: https://www.loxone.com/wp-content/uploads/datasheets/CommunicatingWithMiniserver.pdf
- Denon HEOS CLI protocol spec: https://assets.denon.com/documentmaster/us/heos_cli_protocol_specification_290616.pdf
- Apple HomeKit framework: https://developer.apple.com/documentation/HomeKit
- Home Assistant HomeKit Bridge (exports to Apple Home): https://www.home-assistant.io/integrations/homekit/
- Home Assistant HomeKit Device (pairs supported HomeKit accessories): https://www.home-assistant.io/integrations/homekit_controller
- Spotify Web API: https://developer.spotify.com/documentation/web-api
- Spotify 2026 developer mode change/migration: https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide
- Spotify 2026 quota update: https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates
- Spotify rate limits: https://developer.spotify.com/documentation/web-api/concepts/rate-limits

## Verification checklist
For each connector, record: doc revision, actual model/firmware, API capabilities, auth method, permissions, test fixtures, and physical verification status. Avoid unsupported claims.
