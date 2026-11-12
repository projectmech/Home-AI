# JARVIS — ADVANCED VOICE, PERSONALITY AND HUMOR SYSTEM

> Added 2026-11-12. Mandatory additions to the project. Consolidated from the user's message; requirements are preserved, wording is tightened. It extends the voice sections of prompts 01 (§5) and 02 (§19). The hardware and performance limits in prompt 03 still apply. Where this file and the earlier ones differ, see "Reconciliation" at the end.

## 1. Responds to his name
- Real wake-word detection. Default wake word "Jarvis"; must handle "Jarvis.", "Hey Jarvis.", "Jarvis, are you there?", "Jarvis, turn on the lights.", "Good morning, Jarvis."
- On detection, acknowledge at once by speech or a configurable short activation sound ("Jarvis?" → "Yes?").
- No mouse click or button press when an authorized always-listening voice client is active.
- Configurable sensitivity, noise suppression, false-activation protection, and a follow-up listening window so follow-up questions need no wake word.
- Wake-word detection runs locally whenever possible.
- The Mac mini cannot hear the whole home without microphones or room clients. Architecture must support multiple future voice satellites.

## 2. Expressive, human-sounding speech (high priority)
- Not flat, monotone, mechanical or generic-robotic. Natural, intelligent, calm, confident, conversational.
- Defaults: masculine voice (configurable), clear pronunciation, natural pacing, subtle British-inspired accent, warm but professional, natural pitch/intonation variation, appropriate pauses, subtle emotional variation, occasional dry humor.
- Do not imitate a specific actor's real voice.
- High-quality neural TTS capable of expressive speech, behind a provider-independent speech engine supporting local and external services.
- Voice previews and settings for: voice, speaking rate, expressiveness, pitch (where supported), language, volume, response style. Do not assume every provider supports every parameter; use documented expressive/style controls when available.
- Phrase naturally: "Of course. I've turned on the lights.", never "COMMAND EXECUTED. LIGHTS ACTIVATED."

## 3. Low-latency voice conversations
- Streaming pipeline: wake word → voice activity detection → speech recognition → AI → speech synthesis → audio output.
- Short response delays; generate and play speech incrementally where supported.
- Must support: streaming TTS, speech interruption, barge-in, echo cancellation where available, microphone muting during playback when needed, automatic speech detection, background-noise reduction, configurable response timeout.
- If interrupted mid-sentence, stop and answer the new question.
- No AI request for a simple wake-word acknowledgment.

## 4. Personality engine
- Configurable. Default: intelligent, composed, observant, helpful, sophisticated, slightly witty, confident. Not a scripted support agent.
- Adapts to tone: brief for simple commands, explanatory for complex questions, natural for casual talk.
- Varies acknowledgments. Does not say "sir" in every response. Preferred form of address is configurable.

## 5. Humor
- Intelligent, dry, subtle, occasionally sarcastic, context-aware, natural, not repetitive. Sometimes a witty observation unprompted.
- Style examples (illustrative only; **must not be hardcoded dialogue**):
  - "Jarvis, are you alive?" → "Not in the traditional sense. Although I do spend an unreasonable amount of time thinking about your lighting."
  - "Jarvis, I'm bored." → "I could suggest something productive, but I suspect that's not the answer you're hoping for."
  - "Jarvis, turn on all the lights." → "Certainly. Subtlety is apparently not on the agenda today."
  - "Jarvis, how's the network?" → "Everything is running smoothly. A rare moment of cooperation from your electronics."
- Humor never interferes with accurate device status.
- No joking when: reporting emergencies, handling security incidents, confirming door access, warning of dangerous conditions, responding to a serious or distressed user, reporting critical system failures.

## 6. Humor level (dashboard setting)
0 Off (professional, direct) · 1 Subtle · 2 Balanced (**default**) · 3 Witty · 4 Maximum (more playful and sarcastic, still useful and respectful). Responses vary naturally; not a joke in every sentence.

## 7. Conversational memory
- Persistent and user-controlled. Remembers approved information: preferred room temperatures, favorite music, routines, preferences, conversation language, voice settings, frequently used device names, humor level.
- Example: "I prefer the living room at 21 degrees" → later "make the living room comfortable" may use it, when the user has authorized that behavior.
- Memories are visible, editable and individually deletable in the dashboard.
- A remembered preference never grants permission for a security-sensitive action.

## 8. Voice output and speaker routing
- Outputs: web dashboard, directly attached speaker, room voice clients, compatible Denon/HEOS speakers when supported.
- Distinguish music playback from low-latency voice output. **Do not assume HEOS CLI provides arbitrary real-time speech playback.** Use compatible streaming or audio routing where available.
- Optional music ducking: lower music on wake, restore afterwards; handle interrupted playback and volume restoration safely.

## 9. Voice & Personality settings page
Wake word on/off, sensitivity, speech provider, voice selector, voice preview, speaking speed, expressiveness, language, humor level, personality configuration, follow-up listening duration, microphone selection, audio output selection, room voice clients, voice connection health, audio diagnostics. Administrators can play a sample response with the selected voice.

## 10. Performance (2010 Mac mini, Core 2 Duo)
Lightweight wake-word processing, able to run on room clients; local STT and TTS optional; expressive external TTS supported; efficient streaming; voice never blocks home automation; CPU and memory limits on optional speech services; cache short reusable acknowledgment audio; automatic recovery from voice-service failures. The Rust core stays responsible for all critical device functions. Voice services are independently restartable.

## 11. Acceptance tests
1. Saying "Jarvis" activates an authorized listening client.
2. JARVIS responds with spoken audio.
3. Understands English and Norwegian.
4. Handles a follow-up without the wake word.
5. Can be interrupted while speaking.
6. Natural intonation with a configured expressive TTS provider.
7. Responds humorously when appropriate.
8. Humor level changes conversational style.
9. Becomes serious in critical situations.
10. Remembers and applies approved preferences.
11. Users can inspect and delete saved memories.
12. Voice failures do not interrupt home automations.
13. Microphone permissions and listening status are clearly visible.
14. Speaker routing works with supported devices.
15. Speech engine runs within acceptable resource limits on the target hardware.

## Final objective
An intelligent, responsive, conversational presence: recognizes his name, listens naturally, speaks with realistic intonation, understands context, remembers approved preferences, has a distinctive sense of humor. **Basic browser speech synthesis plus a hardcoded collection of responses is not an acceptable substitute.** Modular, testable architecture with real wake-word detection, speech recognition, conversational intelligence, expressive synthesis, personality controls and proper audio output management.

## Reconciliation with earlier documents (Claude's notes, 2026-11-12; confirm with the user)
- **Always listening vs. privacy default.** Prompt 02 §19 says continuous listening is disabled by default. Reading both together: listening is off until an administrator enables it for a specific, authorized voice client; once enabled, that client needs no click.
- **Browsers.** Prompt 01 §5.4 already notes a phone browser cannot keep a wake-word service running in the background. An open dashboard tab can listen only while it is open and has microphone permission. Hands-free use across rooms needs dedicated room clients with microphones.
- **Security.** Docs/SECURITY.md stands: voice identity alone never authorizes unlock or other high-risk actions, and humor is suppressed for door access.
- **Ordering.** Voice depends on the AI orchestrator (personality and humor are produced by the language model under a configured style, not by canned strings) and on the action policy. It stays after AI in the roadmap.
