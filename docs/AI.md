# The local AI assistant

JARVIS answers what its fixed command grammar does not understand by asking a
**language model running on the same computer**. Nothing leaves the house, and
the model is never trusted with anything.

## How it is wired
- The host talks to the model server through the OpenAI-style
  `/v1/chat/completions` API, so **Ollama** and **llama.cpp's `llama-server`**
  both work and either can be swapped in.
- Default model: `llama3.2:1b` (about 1.3 GB, the fastest sensible choice for this hardware). `llama2-uncensored:latest` (about 3.8 GB) is a one-setting alternative, roughly three to five times slower.
  Change it in the settings (below). Community "uncensored" models have their own
  licences: read the model card before relying on one.
- The model server must listen on this computer (`127.0.0.1` or `localhost`).
  The host refuses any other address.
- The model gets one job: reply with `{"reply": "...", "command": "..."}`.
  `command` is a plain-words home command in the same grammar a person speaks
  ("turn off the kitchen light"). It goes through `voice.rs`, then the normal
  validation, permission and audit path. So the model can only do what the grammar
  and the policy already allow. **It can never unlock anything**, run a program or
  reach the network. A device list in the prompt is marked as data, not
  instructions.
- One question at a time; a time limit (default 60 s); if the model is missing or
  slow the reply says so and **home commands still work**.
- What is said is not stored. The audit log records only that an assistant
  question happened and whether it worked.

## Configure (administrators)
`GET/PUT /api/settings/assistant` with `enabled`, `url`, `model`, `timeout_s`
(5-300), `max_tokens` (16-1024) and `persona` (up to 400 characters);
`GET /api/assistant/status` says whether the server is up and has the model.

## Install the model server (on the Mac mini)
Ollama, then: `ollama pull llama2-uncensored:latest`. Ollama's own binary has not
been shown to run on a Core 2 (see below), so this is not packaged in the OS image
yet.

## Honest limits on a 2010 Core 2 Duo
- **Speed.** A 7B model at 4-bit reads about 3.8 GB of weights for every word it
  writes, on a CPU with no AVX. Expect well under one word per second: a short
  answer can take a minute or more. That is why the time limit exists and why the
  fixed grammar handles everyday commands instantly. A 1B-3B model is far more
  responsive; cloud AI for hard questions was always the plan (CLAUDE.md).
- **CPU support.** The LLM bench (CI run 43650734753) found Ollama v0.40.16 ships
  baseline CPU backends with no AVX (`libggml-cpu-x64.so`, `libggml-cpu-sse42.so`,
  the latter needing SSE4.2, which a Core 2 lacks) but `ollama serve` itself died
  with an illegal instruction on an emulated Core 2 before logging anything. Until
  that is solved (for example by building llama.cpp from source for the Core 2),
  the model server may have to run on another computer; the host will not talk to
  it unless a loopback tunnel is set up on purpose.

## Decision (owner: "choose what is best")
1. **What answers fast is the grammar, not the model.** Everyday commands never
   touch the model; they are instant. The model is only for open questions.
2. **Default model: a small one (`llama3.2:1b`).** On a Core 2 Duo with no AVX the
   speed of a model is set by its size: roughly 1B is usable (a few words a
   second at best), 3B is slow, 7B (`llama2-uncensored`) is a minute or more per
   answer. A 7B model stays available as a setting for people who accept the wait.
   These speeds are estimates: only `llm/bench-models.sh` run on the Mac mini
   gives real numbers.
3. **Model server: llama.cpp's `llama-server`, built for the Core 2, is the target;
   Ollama stays supported.** Ollama's own server crashed on an emulated Core 2
   (see above); both speak the same API, so the host does not care which runs. The
   server will be packaged in the OS image once a build is shown to run on the
   emulated Core 2 in CI.
4. **Hard questions: cloud AI, as an opt-in.** Not built; the settings and the
   loopback rule above would need a deliberate change.
5. **Safety does not depend on the model.** An "uncensored" or any other model can
   say what it likes; what it can DO is decided by the grammar and the policy.

## Update 2026-11-15: a Core 2 CAN run llama.cpp; earlier "needs AVX" verdicts were a test artifact
- The CI runner (ubuntu-latest) has a C library that refuses to run on an emulated
  Core 2 ("CPU does not support x86-64-v3"), so EVERY program stopped at the same
  instruction there, including a llama.cpp with no AVX at all. The earlier verdicts
  for Vosk, whisper.cpp and Ollama's binary ("needs AVX / a Haswell CPU") were
  therefore not evidence about those programs.
- Inside `debian:trixie` (the OS image's base, baseline x86-64 C library) the same
  tests behave: an ordinary program runs on an emulated Core 2, and **llama.cpp's
  `llama-server`, built from source with `-march=core2`, runs and generates text on
  an emulated Core 2 (Penryn), Nehalem, SandyBridge and Haswell** (CI run
  43654703294, llama.cpp tag v1.0.0, commit b1b770d). Its binary contains no AVX, no
  SSE4.2 and no POPCNT. The only instruction a Core 2 lacks that it does contain is
  `lzcnt`, inside the FLAC audio decoder the server bundles; nothing in this project
  decodes FLAC.
- This confirms decision 3: the target model server is `llama-server` built for the
  Core 2. Not yet done: package it in the OS image, run it as a service on
  127.0.0.1, and fetch a pinned GGUF model. Real speed still needs the Mac mini.
- Vosk and whisper.cpp are worth retesting in the same container (workflow "Voice
  bench (Vosk and whisper.cpp recheck)", run by hand). Vosk got 8 of 8 synthetic
  commands natively against PocketSphinx's 7 of 8.

## Evidence 2026-11-15: the chosen model works with the assistant's prompt
CI run 43655313631 (llama-server built for a Core 2, run natively on a modern CI CPU
with 2 threads): Qwen2.5-1.5B-Instruct Q4_K_M, 1,117,320,736 bytes, SHA-256
`6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` (now pinned in
`jarvis-model`). It answered the assistant's JSON prompt correctly: for "it is cold and
dark in the kitchen, switch the light on please" it returned
`{"reply": "switch the light on in the kitchen", "command": "turn on the kitchen light"}`,
which the grammar accepts. Speed on that runner, without AVX: reading 5 and writing 4
tokens a second. A real Core 2 will be slower (not measured). The OS image build
(run 43655313679) compiled llama-server in the image, passed the no-AVX guard and the
ISO inspection (model server, `jarvis-model` and its unit present). Not yet shown: a
model installed and answering inside an installed image, or any speed on the Mac mini.
