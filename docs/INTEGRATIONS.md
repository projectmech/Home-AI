# Connector scope, capability boundaries and prerequisites

All connectors must be optional and fault-isolated. Discovery is read-only; execution goes through auth and policy. Unknown device models must be represented explicitly. Store credentials only through encrypted or restricted server-side secret storage.

| Connector | First useful capabilities | Requirements / open dependencies | Major caveat |
|---|---|---|---|
| Loxone | discover rooms, control types, state updates, lights/heating/blinds/scenes | Miniserver generation/firmware, authenticated account, LAN access | implement official structure file, token auth, WebSocket behavior; no guessed commands |
| Apple Home | compatible accessories via viable pairing/bridge/companion approach | clarify which accessories are already paired, Apple device/platform, Matter/Thread gateways | exposing devices to Apple Home is **not** the same as reading existing Home data |
| Denon/HEOS | discover compatible players, volume, play/pause, grouping, input where supported | exact AVR/speaker models and LAN reachability | HEOS CLI and AVR APIs differ |
| Spotify | account authorization, allowed playback/search/playlist APIs | Spotify Premium and developer app eligibility | endpoint restrictions/quota and device compatibility change; verify current docs |
| Yale | confirmed lock/battery/door status, authenticated locking/unlocking where supported | exact lock model, hub, app, protocol support | never allow unauthenticated voice unlock; model-dependent local/cloud paths |
| Network | authorized LAN inventory, ping/DNS/gateway health, monitored services | router make/model, subnets, VLANs, management API access | discovery alone cannot guarantee Wi-Fi/traffic/router configuration data |
| Home Assistant (optional) | entity discovery/state/actions as a compatibility bridge | separate HA instance if chosen | never foundational core |

## Connector acceptance contract
1. Show current auth/connection status and applicable permission scope.
2. Register real device capabilities, not assumed ones.
3. For actions, return verified success / failure / unknown where verification not possible.
4. Recover from service and LAN outages without crashing the core.
5. Have simulator fixtures + contract tests; flag physical testing status separately.
6. Revoke tokens and remove connector data safely when disconnected.
7. No cross-connector accidental duplication without explicit association.

## Implementation order
Loxone, HEOS/Denon, Spotify, then Apple Home path, Yale once model is known, and network/router expansions. Foundation and simulator come before all of these.
