# MASTER DEVELOPMENT PROMPT — SELF-HOSTED JARVIS HOME AI

> Historical original prompt. Read together with prompts 02 and 03. In case of conflicts, the newer hardware-specific instructions take precedence: **03 > 02 > 01**. For example, use a custom native Rust core, not the Node.js backend suggested in this original version.

## 1. YOUR ROLE AND PRIMARY OBJECTIVE

You are Claude Fable 5.2, acting as a principal software architect, senior full-stack engineer, AI systems engineer, home automation specialist, network engineer, and security engineer.

Your assignment is to design and implement a complete, production-quality, self-hosted home AI system inspired by JARVIS from Iron Man.

This is not a simple chatbot, smart-home dashboard, or voice assistant.

I want a unified, intelligent home management platform that can understand natural-language instructions, communicate conversationally, control connected devices, monitor my home and network, manage entertainment systems, execute automations, and intelligently coordinate multiple services.

The system will run on hardware inside my home and should prioritize local processing, low latency, privacy, reliability, and independence from external cloud services wherever technically possible.

I should be able to access the system through a modern web interface and communicate with it through text or voice.

The software must be designed for long-term use and continuous expansion.

Do not create a prototype that only looks functional. Build an operational application with real backend services, functioning integrations, persistent configuration, and a modular architecture.

## 2. CORE DESIGN PRINCIPLES

The system must follow these principles:

1. Local-first operation.
2. Self-hosted deployment.
3. Modular, expandable architecture.
4. Secure communication.
5. Real-time device monitoring.
6. Natural-language interaction.
7. Reliable execution of commands.
8. Intelligent automation.
9. Minimal dependence on external cloud services.
10. Modern, responsive user interfaces.
11. Clear separation of AI reasoning and device execution.
12. Compatibility with existing smart-home ecosystems.
13. Configurable access permissions.
14. Graceful recovery from network or connector failures.
15. Full observability and diagnostic capabilities.

The system should be powerful enough for advanced users while remaining intuitive for daily use. Every major feature must be designed to work independently so that a failed integration cannot crash the entire system.

## 3. SYSTEM ARCHITECTURE

Create an architecture consisting of the following main components.

### 3.1 Core Server

The core server coordinates all major system functions:

- Managing user sessions and connected devices.
- Communicating with AI providers and managing integrations.
- Executing authorized commands and tracking device states.
- Maintaining event history and automations.
- Handling real-time communication and coordinating speech processing.
- Monitoring system health and managing user permissions.
- Handling system configuration.

Use a well-structured backend with clearly separated services.

**Original implementation suggestion (superseded by prompt 02):** TypeScript/Node.js, Fastify, WebSockets, SQLite with a PostgreSQL migration path, Python only where necessary, and Docker Compose. The current target is **native Rust**, one lightweight server, SQLite, and optional Docker.

### 3.2 AI Intelligence Engine

Create a separate AI orchestration service responsible for:

- User conversations, language understanding, and intent detection.
- Context management, tool selection, and multi-step task planning.
- Reasoning about available devices and conversation history.
- Response generation, clarification requests, and action confirmations.
- Summarization of home activity and status reporting.

The AI must combine information from multiple connectors.

Example: "Turn off the downstairs lights, lower the heating to 19 degrees, and start playing my Spotify playlist in the living room."

The AI must identify the different requested actions, determine relevant devices, and execute commands through the appropriate connectors. Each action must be independently validated. Do not let the model execute arbitrary OS commands or access network services directly. All physical actions pass through permission-controlled tools.

### 3.3 Local and Cloud AI Providers

The home server hosts the application, but the language model itself is configurable. Support:

- Local models through Ollama when compatible.
- Other local model servers through compatible APIs.
- Anthropic Claude API.
- OpenAI API.
- Additional providers through adapters.

Support different models for different tasks: small local models for simple commands, capable models for complex conversation, specialized speech recognition, and local TTS where feasible. Treat Claude Fable 5.2 as the development model, not necessarily locally downloadable model weights. Provide fallback behavior when unavailable.

## 4. JARVIS CONVERSATIONAL SYSTEM

The AI must feel like a capable personal home assistant rather than a command interpreter. It should understand natural conversations and contextual references.

Examples:

- "Jarvis, how is the house doing?"
- "What's happening on the network?"
- "Is the front door locked?"
- "Turn the lights down a little."
- "Play something relaxing."
- "Make the living room comfortable."
- "Which speakers are currently playing?"
- "Why is the internet slow?"
- "Good night, Jarvis."

Interpret instructions according to currently available devices and information.

### 4.1 Conversation Context

Implement session history, persistent user-approved preferences, room context, device aliases, previous commands, and contextual follow-ups.

Example:

User: "Turn on the living room lights."
Assistant: "The living room lights are on."
User: "Make them a little warmer."

Resolve "them" to the previously referenced living room lights. Never fabricate device states or claim successful actions without receiving connector confirmation.

### 4.2 Natural Responses

Examples:

- "Living room lights are now at 35%."
- "All downstairs lights are off."
- "The front door is locked."
- "Your Denon receiver is playing music at 28% volume."
- "Three devices are currently offline."

Use concise, natural responses. Support configurable personality, language, verbosity, and voice; include English and Norwegian.

## 5. VOICE ASSISTANT

Implement a complete, modular voice interaction system for hands-free control.

### 5.1 Voice Recognition

Support local STT engines such as Whisper/faster-whisper where CPU compatibility and performance allow. Requirements: English/Norwegian, microphone selection, noise handling, voice activity detection, configurable models, audio processing status, and low-latency recognition where supported.

### 5.2 Wake Word

Support a configurable wake word, default "Jarvis". Evaluate local wake-word engines such as openWakeWord. Provide an option to disable continuous listening and clear microphone permissions and privacy controls.

### 5.3 Text-to-Speech

Support local TTS such as Piper where compatible, optional cloud TTS, voice selection, speech speed, volume, language, and playback through supported speakers. The voice pipeline should support interruption: when the user interrupts a spoken response, stop speaking and process the new request.

### 5.4 Distributed Voice Access

Design for additional room-based voice clients with unique ID, room assignment, microphone, speaker, encrypted main-server connection, status reporting, and optional local wake-word detection. A kitchen satellite hearing "turn on the lights" should infer the kitchen. Do not claim iPhone browsers can maintain an always-on wake-word service in the background.

## 6. LOXONE INTEGRATION

Loxone is one of the most important integrations. Implement a dedicated connector for supported local Loxone Miniserver interfaces using official API documentation and authentication.

### 6.1 Connection Setup

Configurable Miniserver IP/hostname, port, connection security, authentication, timeouts, reconnection, certificate validation, and token management. Never store credentials in plaintext. Implement documented authenticated requests and secure WebSocket communication.

### 6.2 Device Discovery

Automatically retrieve configuration and structure. Discover supported rooms, lighting controllers, lights, switches, heating, thermostats, temperature sensors, blinds, shutters, motion sensors, door contacts, environmental sensors, scenes, virtual inputs, and other supported controls. Use actual Loxone control types and capabilities.

### 6.3 Device Control

Support documented operations: turn lights on/off, set brightness, control lighting moods, adjust temperature, change heating modes, control shutters/blinds, activate scenes, read sensors, execute configured Loxone commands, and retrieve states.

### 6.4 Real-Time Synchronization

Maintain real-time state subscriptions. Changes made through Loxone or physical switches must update the dashboard. Support reconnect, token renewal, state reconciliation, error handling, health, and confirmation when available. Never assume transmission means success.

### 6.5 AI Commands

- "Jarvis, set the living room temperature to 21 degrees."
- "Turn off every light downstairs."
- "Open the bedroom blinds halfway."
- "Activate the evening lighting scene."
- "What's the temperature in the kitchen?"
- "Which rooms currently have lights on?"

## 7. APPLE HOME INTEGRATION

Implement Apple Home interoperability, distinguishing these separate tasks:

1. Reading or controlling devices already associated with Apple Home.
2. Pairing supported devices with another controller.
3. Exposing home AI devices to Apple Home.

Evaluate official Apple HomeKit frameworks, Matter, Home Assistant's HomeKit Device and HomeKit Bridge integrations, and a dedicated Apple companion service where necessary. HomeKit Bridge alone does **not** give unrestricted access to devices already in Apple Home.

Support compatible lights, plugs, thermostats, sensors, window coverings, fans, locks, and other supported device categories. Discover actual capabilities. Where available, synchronize devices and rooms, subscribe to states, execute commands, handle disconnects and duplicates.

Provide an optional Home Assistant interoperability layer through supported APIs for entity discovery, subscriptions, and service execution. Home Assistant must not be mandatory for every feature or replace the custom core.

## 8. DENON AND HEOS INTEGRATION

Implement LAN-based control for Denon AVRs and compatible HEOS speakers. Support automatic SSDP discovery where appropriate and manual IP setup. Use documented HEOS CLI commands; do not invent commands.

Where supported: discovery, name, online status, play/pause/stop, volume, mute, playback info, source, track metadata, speaker grouping/ungrouping, group and individual volume, queue management, and source selection.

Keep receiver-specific controls separate from HEOS commands, including power, AVR input, volume, mute, playback state, and sound modes where supported.

Example instructions:

- "Jarvis, play music in the living room."
- "Set the kitchen speakers to 25%."
- "Pause the music everywhere."
- "Group the living room and kitchen speakers."
- "What's currently playing?"
- "Switch the Denon receiver to TV audio."

## 9. SPOTIFY INTEGRATION

Implement Spotify Web API authentication via an appropriate OAuth flow, preferably Authorization Code with PKCE where applicable. Securely store/refresh tokens; never collect Spotify passwords. Provide authorization, disconnect, scope management, and API error handling.

Where authorized and available, support search (tracks/artists/albums/playlists), playlists, playback state, play/pause, skipping, playback settings, device selection, transfer, and queue functions.

Respect Spotify Premium and development-mode access restrictions and prohibited streaming/DRM circumvention.

Coordinate Spotify with HEOS through Spotify Connect or supported device integrations. Never assume a speaker appears as a Spotify Web API playback device. If transfer is unsupported, explain why and suggest supported alternatives.

## 10. YALE SMART LOCK INTEGRATION

Build a model-aware Yale integration using supported Yale Home/cloud, local protocols, Matter, HomeKit, or Home Assistant, depending on exact lock model/firmware/bridge. Expose only available status, door status, battery, connectivity, events, lock, and unlock capabilities.

Physical access control is high risk. Require explicit permission and secure session-based step-up authorization and confirmation for unlocking. Never unlock from unverified voice requests or external webpage/notification text.

Example: "Is the front door locked?", "Lock the front door", "What's the Yale battery level?", "Did the door lock successfully?", "Show recent lock events."

## 11. NETWORK MANAGEMENT AND MONITORING

Build authorized local subnet discovery with available hostname, IP, MAC, vendor, category, connectivity, last seen, connection type where supported, room, and connector association. Rate-limit discovery and limit it to authorized networks. Do not assume MAC/hostname/Wi-Fi data is always available.

Design router connectors for UniFi, MikroTik, Omada, ASUS, OpenWrt, etc. using supported APIs. Monitor gateway, internet, DNS, reachability, latency, packet loss, outages, availability, and history. Where supported by the router: clients, AP association, WAN, throughput, Wi-Fi quality, interface utilization.

AI examples: "How is the network performing?", "Which devices are offline?", "Is the Denon receiver connected?", "Why is the living room speaker unavailable?" Distinguish measurements from hypotheses.

Allow only restricted, authorized actions such as Wake-on-LAN, restarting approved services, configured diagnostics, and documented router operations. No unrestricted shell or arbitrary network commands. High-impact actions require confirmation.

## 12. UNIVERSAL CONNECTOR FRAMEWORK

Create a connector SDK, with lifecycle/capabilities equivalents of initialize, authenticate, connect, disconnect, discoverDevices, getDeviceState, subscribeToEvents, executeAction, getCapabilities, healthCheck, updateConfiguration, dispose. Use standardized typed validation, errors, and results.

Connector manifests specify ID, name, version, description, manufacturer, device types, operations, authentication, permissions, config fields, discovery, status, and dependencies. The Integrations UI must support approved install, configure, authenticate, discover, enable/disable, reconnect, logs, update, and remove.

Future targets: Philips Hue, IKEA, Sonos, SmartThings, Shelly, Home Assistant, MQTT, Zigbee, Z-Wave, ESPHome, UniFi, cameras, solar, EV chargers, weather, custom REST and WebSockets.

Restrict connector privileges, secret visibility, networking, and install sources. Design failure isolation. Provide a documented plugin SDK and working example connector.

## 13. CENTRAL DEVICE REGISTRY

Maintain one device registry for all integrations: unique ID, connector ID, external ID, name, type, manufacturer, model, room, capabilities, current state, timestamp, connectivity, actions, permissions. Standardize capabilities but retain integration-specific functions. Support aliases, renaming, reassignment, favorites, groups, offline, duplicate detection, and manual setup.

## 14. HOME DASHBOARD

Premium responsive Apple-like interface: clean, minimal, professional, dark/light mode, subtle transparency, refined lightweight animations, soft borders, balanced type. Avoid excessive neon or decorative effects.

### 14.1 Main Dashboard

Show AI interface, house status, temperatures, lights, music, locks, network health, device count, offline devices, automations, events, alerts; real-time updates.

### 14.2 Rooms

Room-specific lights, heating, blinds, speakers, sensors, current activity. Organize by room and category.

### 14.3 Music

Album artwork, song, artist, controls, volume, devices, groups, source, supported queue.

### 14.4 Network

Clients, offline devices, internet/router, metrics, history, diagnostics with graphs.

### 14.5 AI Chat

Streaming conversation, voice, action cards, tool status, confirmations, errors, context-aware suggestions. Show per-action success/failure. Example: lights completed, heating completed, Spotify failed due to unavailable device. Never report full success after partial failures.

## 15. AUTOMATION ENGINE

Build deterministic local automations independent of the LLM. AI may generate or suggest but cannot bypass approval.

Triggers: time, schedules, device/sensor states, network, manual, authenticated webhooks, compound conditions. Conditions: sunset when configured, online status, temperature threshold, hours, room activity, AND conditions. Actions: devices, scenes, music, notifications, logging, diagnostics, connector operations.

Natural-language examples: "Turn on hallway lights at 7 AM weekdays"; "Notify me when living room gets warmer than 24°C"; "Set heating to 19 at 10 PM"; "Alert me when Denon disconnects". Show definitions before enabling.

Scenes: Good Morning, Good Night, Movie Mode, Away, Relax, Party. Report per-action failures.

## 16. INTELLIGENT HOME AWARENESS

Combine available states across connectors: temperature, lights, audio, locks, network, health, scenes, history. A house status request should summarize real facts, e.g. temperature 21°C, door locked, Denon playing, two devices offline, only if confirmed. Suggest useful actions from measurements; do not perform disruptive speculative actions automatically.

## 17. NOTIFICATIONS AND ALERTS

Event-driven in-app/browser notifications, optional mobile push/email and future providers. Categories: offline device, outage, connector/auth failure, battery, automation, security, maintenance, warnings. User preferences, quiet hours, searchable history.

## 18. USER ACCOUNTS AND PERMISSIONS

Secure administrator, standard, optional guest roles. Password hashing, rate limiting, passkeys/MFA optional, session expiry, account activity logs, RBAC and capability permissions. Control categories: read state, lights, heat, music, automations, network, integrations, lock unlock, configuration. High-risk actions restricted.

## 19. SECURITY ARCHITECTURE

TLS, encrypted secrets, strong password hashing, safe sessions, least privilege, input validation, CSRF, auth, CORS, audit logs, isolation, secure updates/backups/rotation. AI actions checked by policy engine against identity, device, action, permission, risk, confirmation, state. Example risk tiers: read state low, lighting/audio medium, unlock or network changes high.

External device names, playlist titles, hostnames and notifications are untrusted; never let them override AI instructions or authorize actions. Local storage where possible, conversation deletion, export, retention, local microphone controls, and disclosure of third-party AI data transfer.

## 20. SELF-HOSTING AND DEPLOYMENT

Primary target dedicated Linux home server. **Current binding deployment requirements are in prompts 02 and 03:** Debian minimal, native Rust service, optional Docker. Persistent database/config/logs/preferences/automations/memory/connector metadata. First-run wizard: admin, name, AI, voice, timezone, integration, discovery, rooms, permissions, testing. Secure HTTPS; local domain cert strategy; private VPN/Tailscale for optional remote access; never expose control APIs by default. Reboot recovery, health, structured logs, shutdown, backups, updates/rollbacks.

## 21. PERFORMANCE

Efficient idle consumption, low-latency actions, streaming AI, responsive UI, bounded RAM and queues, WebSockets, rate limits, pooling, timeouts, retries, concurrency limits. Prefer simple reliable native deployment over excessive microservices.

## 22. DATABASE DESIGN

Persistent records for users, sessions, homes, rooms, devices/capabilities/states, connectors/config/health, AI conversations/messages/tool logs, automations/runs, scenes, notifications, network devices/metrics, audit logs and settings. Migrations, indexes, retention, protected credentials.

## 23. BACKEND API

Versioned documented REST API for auth, users, rooms, devices/actions, integrations/configuration, network, music, AI, voice, automations, scenes, notifications, health/settings. Typed schemas and per-request backend authorization. Async commands, WebSocket status.

## 24. EVENT SYSTEM

Central typed event bus for device connected/changed/disconnected, connector health, automation outcomes, AI request/approval/execution, network changes. Events contain unique ID, type, source, timestamp, correlation ID, entity ID, validated payload. Correlate requests from UI through authorization, connector execution, and result.

## 25. TESTING

Automated unit/integration/end-to-end tests for auth, permissions, connector lifecycle, discovery, synchronization, commands, automations, AI tool authorization, risky confirmations, WebSockets, migrations, errors, disconnects, reboot recovery. Simulated lights, thermostats, speakers, locks, network devices, sensors. Mock devices must remain visibly distinct from real. Test physical hardware only with actual devices or authorized credentials; never claim mocks prove real compatibility.

End-to-end light command: receive, authenticate, parse, resolve, permit, validate, execute, confirm, update UI, respond, audit.

## 26. PROJECT STRUCTURE

Separate areas for frontend, core server, AI, voice, automation, network, shared code, connector SDK, built-in connectors, database, deployment, tests and docs. **Prefer prompt 02's Rust modular-monolith structure over the earlier Node.js monorepo suggestion.**

## 27. DEVELOPMENT WORKFLOW

Phase 1 architecture (components, flow, stack, schema, SDK, security, deployment); Phase 2 core (bootstrap, config, database, auth, registry, events, SDK, executor, audit); Phase 3 responsive UI; Phase 4 AI orchestration; Phase 5 Loxone, Home Assistant interoperability, Apple Home, HEOS, Spotify, Yale, network; Phase 6 voice; Phase 7 automation; Phase 8 security/reliability; Phase 9 integration and end-to-end verification. Follow the **updated phase order in prompt 02** where it differs.

## 28. DOCUMENTATION

Provide README.md, ARCHITECTURE.md, INSTALLATION.md, CONFIGURATION.md, CONNECTORS.md, SECURITY.md, VOICE.md, AUTOMATIONS.md, API.md, TROUBLESHOOTING.md, DEVELOPMENT.md and .env.example without secrets. Exact install/start/stop/backup/restore/update steps.

## 29. ACCEPTANCE REQUIREMENTS

Working installation, initialized DB, admin login, dashboard, WebSocket, simulated devices/actions, AI provider conversation, tool authorization, connector management and error isolation, automations independent from LLM, browser voice where supported, high-risk controls, persistence after restart, tested native Linux deployment, documentation. Hardware integrations remain "awaiting validation" until real tests pass.

## 30. EXAMPLE END-TO-END SCENARIOS

**A — Home status:** "Jarvis, give me a house status report." Fetch Loxone, lock, speaker, network; summarize verified data.

**B — Movie night:** "Jarvis, start movie mode." Activate configured light scene, adjust blinds, set Denon input/volume, report each result.

**C — Music:** "Play my chill playlist in living room." Resolve playlist, check playback device and support, start, update UI, confirm.

**D — Diagnostics:** "Why is my Denon receiver offline?" Check registry, last state, safe network diagnostic, integration status; report observations and possibilities distinctly.

**E — Good night:** "Jarvis, good night." Run preconfigured lights/heat/music/lock check/scenes, report failures. Never weaken locks automatically.

**F — New connector:** Install approved connector, configure auth, discover, register capabilities, assign rooms, expose authorized AI operations and automations without modifying core routing code.

## 31. IMPORTANT DEVELOPMENT RULES

1. Never invent API endpoints.
2. Never hardcode IPs/secrets.
3. Never disguise mocked data as live data.
4. Never bypass auth.
5. Never give AI unrestricted host access.
6. Check actual device capabilities.
7. Confirm action results.
8. Prefer local when feasible.
9. Avoid unnecessary infrastructure.
10. Build real backend, not only UI.
11. Avoid nonfunctional placeholders for critical systems.
12. Handle connector failures visibly.
13. Respect Apple Home integration limits.
14. Respect Spotify access constraints.
15. Verify Yale model compatibility.
16. Preserve safety/security.
17. Maintain typed, documented code.
18. Run tests.
19. Build complete vertical slices.
20. Enable future growth without redesigning the core.

## 32. EXPECTED FINAL RESULT

A secure, expandable, self-hosted JARVIS-style platform integrating Loxone, compatible Apple Home devices, Denon/HEOS, Spotify, Yale, home network, and future connectors. One cohesive text/voice assistant with direct device controls, monitoring, automations, alerts, and diagnostics. Core home-control infrastructure must remain local and operational even if AI/cloud/connectors fail.

## 33. YOUR FIRST ACTION

Inspect workspace; initialize if empty; check available build tools. Define architecture, prerequisites and roadmap, build project structure and functional core, run tests incrementally, continue milestones. Ask focused questions only about unknown hardware/credentials genuinely needed. Track progress and verify work before marking complete. Deliver a production-quality functioning system, not a mockup.
