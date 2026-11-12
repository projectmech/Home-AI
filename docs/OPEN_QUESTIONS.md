# Missing facts — ask only when blocking the next task

## Hardware and development
- Is the 256 GB drive an HDD or SSD? Model/SMART output?
- Actual CPU flags; currently installed OS; storage health; target boot mode?
- Will Claude Code run on a modern Mac/Windows/Linux computer with access to a Git repository?
- Is the Mac mini wired to the LAN and stable on headless Linux?

## Loxone
- Miniserver generation and firmware version?
- Which rooms, lighting/heating/blind controls, and user permissions exist?
- Accessible local IP/hostname? (Do not store private address/credentials in public artifacts.)

## Apple Home
- Which existing Apple Home accessories, which Matter/Thread devices, and which Apple hubs/controllers?
- Is the requirement **control existing Apple Home accessories**, **expose core devices to Apple Home**, or both?
- Is an Apple-platform companion service acceptable?

## Audio
- Exact HEOS speaker and Denon receiver model numbers?
- Spotify Premium and developer account availability?
- Should playlist playback use Spotify Connect, HEOS built-in Spotify integration or both where supported?

## Yale and networking
- Exact Yale lock model and compatible hub/bridge; supported protocol?
- Router make/model, network segments/VLANs, available router API?
- Intended read-only monitoring vs explicit admin-approved router management?

## UI / security
- Local-only website or remote access via VPN also needed?
- Desired hostname/domain, TLS trust installation method, number of household users and role needs?
- Which preferred cloud AI provider and voice language/voice service?

Unknown answers should **not** block unrelated simulated-core milestones.

## Voice (prompts/05)
- Which expressive TTS provider, and is sending speech text and audio to a cloud provider acceptable?
- Which microphones and speakers exist, in which rooms? What hardware for room voice clients?
- Should an open dashboard tab be allowed to listen for the wake word, or only dedicated clients?
- Preferred form of address and default language (English or Norwegian)?
