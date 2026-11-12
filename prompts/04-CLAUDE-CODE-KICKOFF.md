# COPY AND PASTE THIS INTO CLAUDE CODE

Read `CLAUDE.md` and the documentation inside `docs/`, and the three detailed prompts inside `prompts/`.

Apply precedence **03 > 02 > 01** whenever requirements differ. The current architecture is a **native Rust modular monolith on Debian minimal**, not a Node.js or Home Assistant-based core. The target machine is a **Mid-2010 Mac mini, 16 GB DDR3 RAM, 256 GB drive (SSD/HDD unknown)**. The system needs a **secure web login and a full server administration dashboard**, plus Loxone, Apple Home interoperability, HEOS/Denon, Spotify, Yale, network management, AI and future connectors.

Treat the project documents as requirements, not evidence that the implementation is complete. Inspect the existing repository and installed development tools. Then:

1. Produce a concise architecture decision record and update the roadmap.
2. Establish a tested, target-compatible Rust workspace with SQLite, Web API, static web assets, and event bus.
3. Implement first-run admin creation, secure authentication, authorization and HTTPS strategy.
4. Implement a real, mobile-responsive Svelte dashboard with authenticated system metrics and WebSocket updates.
5. Add simulated device discovery and control, with integration SDK and tests.
6. Add optional AI-provider settings, strictly permission-controlled tool execution, and confirmation for high-risk actions.
7. Implement real connectors one by one, explicitly labeling any that require physical hardware for final verification.
8. Write deployment instructions for Debian on Macmini4,1, compile the Linux release binary with a conservative x86-64 ISA target, and test on actual hardware when available.
9. Run formatting, linting, builds, security checks and automated tests as features are developed; do not claim success without results.
10. Update project progress and record blockers clearly.

Do not make a UI-only mockup, fake integration responses, or claim hardware compatibility that has not been tested. Keep essential home control available without an AI provider. Do not ask for user passwords or API tokens in chat; use protected local configuration.

Begin implementation of the first complete, testable vertical slice now.
