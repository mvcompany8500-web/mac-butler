# Security

Mac Butler listens all the time and can act on your computer, so it is built to fail closed.

## Design

| Risk | What Mac Butler does |
|---|---|
| Someone (a TV, a video, a web page) says a command | Quick commands only open apps, search, play media or type what *you* dictate. Handing a task to a Claude Code session always asks **“Hand this to Claude?”** and waits for a spoken yes (`confirmDelegate`). |
| Prompt injection into the assistant’s brain | **Safe mode (default):** the Claude process gets a fixed tool allowlist — the bundled `jax` / `jtype` tools, `butler delegate` (still confirmed), `date`, reading its own screenshot folder, web search. No arbitrary shell, no file writes, no fetching URLs, no MCP servers, and your own Claude settings are not loaded. `brainAccess: "full"` turns this off — only if you understand the risk. |
| The assistant pressing things it shouldn't | In safe mode `jax`/`jtype` refuse to click, type or press keys in terminals, code editors, the Claude app, System Settings, Keychain/Passwords, password managers and macOS permission prompts. They only open `http(s)` URLs and non-protected apps. |
| Other programs sending commands | The control channel is a Unix socket in `~/.macbutler` (mode 0600) and every connection's user id is checked. Sandboxed apps and other users can't reach it. |
| A fake transcription server | Whisper runs on a random loopback port each launch and is only used while the process Mac Butler started is alive. |
| Tampered model download | `scripts/download-model.sh` verifies the SHA-256 published by Hugging Face. |
| Your data | Audio never leaves the Mac. `~/.macbutler` (settings, logs with what you said, socket) is owner-only; logs rotate at 5 MB. Only the text of commands that go to Claude (Anthropic) and, if enabled, spoken answers (ElevenLabs) leave the Mac. |
| Tampered app | Releases are signed with Developer ID and notarized by Apple; SHA-256 is published with each release. CI uses pinned actions with read-only permissions. |

## Reporting a vulnerability

Please **do not open a public issue.** Use GitHub’s private reporting: *Security → Report a vulnerability* on this repository.
We aim to reply within 72 hours.
