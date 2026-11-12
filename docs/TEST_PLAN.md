# Acceptance tests and evidence

## Initial vertical slice
| ID | Test | Evidence required |
|---|---|---|
| A01 | First-run setup creates admin, cannot be rerun | automated integration test + manual screenshot |
| A02 | Incorrect password denied and rate-limited | auth test run |
| A03 | Anonymous user cannot read device APIs or WebSocket | integration test |
| A04 | Authenticated user sees real or correctly identified simulated server data | web/browser test |
| A05 | Device command validated by permission and capability policy | unit + integration tests |
| A06 | Simulated light state updates via WebSocket and persists if appropriate | e2e test |
| A07 | Server reboot/restart recovers with consistent database | restart test |
| A08 | x86-64 build runs without unsupported instruction error on target CPU | real Mac mini smoke test |

## Integration tests
| ID | Test | Evidence required |
|---|---|---|
| C01 | Connector discovery/register/disconnect with mocked fixture | contract test |
| C02 | Connector disconnection does not crash core | fault injection |
| C03 | Command partially succeeds across devices and reports each outcome | e2e test |
| C04 | Vendor command follows current official API and hardware capability | contract + optional physical verification |
| C05 | Token refresh/revoke and secret redaction | auth/security tests |
| C06 | Physical device behavior | mark `NOT TESTED` until actual hardware accessed |

## Security and reliability tests
- CSRF/XSS/session expiry/privilege escalation.
- Prompt-injection attempt through a device name and track title.
- Lock unlock attempt from unauthenticated voice must be rejected.
- Backup and restore verified on a separate environment.
- CPU, RAM, disk I/O and latency measured on target hardware; performance targets are not guaranteed.
- App must continue direct controls and scheduling with AI provider offline.
