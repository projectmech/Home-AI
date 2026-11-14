# The local AI assistant

JARVIS answers what its fixed command grammar does not understand by asking a
**language model running on the same computer**. Nothing leaves the house, and
the model is never trusted with anything.

## How it is wired
- The host talks to the model server through the OpenAI-style
  `/v1/chat/completions` API, so **Ollama** and **llama.cpp's `llama-server`**
  both work and either can be swapped in.
- Default model: `llama2-uncensored:latest` (Ollama library, about 3.8 GB).
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
