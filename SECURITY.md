# Security

Mac Butler listens all the time and can act on your computer, so it is built to fail closed.

## Design

| Risk | What Mac Butler does |
|---|---|
| Someone (a TV, a video, a web page) says a command | Quick commands only open apps, search, play media or type what *you* dictate. Anything the brain wants to hand to a full-power Claude Code session always waits for a spoken yes, in every mode; "right away" (`confirmDelegate: never`) applies only to a hand-off you ask for directly ("클로드한테 …"). |
| Prompt injection into the assistant’s brain | **Safe mode (default), for every brain:** the brain gets only Mac Butler's tool box, served by the bundled `butler-mcp` (press, type, open, look, hand over, time) plus web search where the provider has it. No shell at all, no file reads or writes, no fetching URLs, no other MCP servers, and your own Claude settings are not loaded. The safe-mode flags are fixed in the MCP server's launch environment, where the brain can't change them. `brainAccess: "full"` turns this off — only if you understand the risk. |
| The assistant pressing things it shouldn't | In safe mode the tools refuse to click, type or press keys in terminals, code editors, the Claude app, System Settings, Keychain/Passwords, password managers and macOS permission prompts, and never type into password fields. They only open `http(s)` URLs and non-protected apps. |
| The assistant sending, paying, posting or deleting | Buttons named like send / pay / buy / order / post / publish / delete, Enter or Space on them, Enter in messengers, ⌘/⌃+Enter, and Enter in a browser form field are held by the tool itself: Mac Butler asks out loud and presses after your yes, in the same app — without asking only when you said exactly that while holding the hotkey. Line breaks in text the brain types become spaces. Hosts it remembers for 「다 꺼」 are plain host names only before they reach AppleScript. Every press, keystroke and open is logged to `~/.macbutler/logs/actions.log` (owner-only). |
| API keys | Keys for API brains and paid voices live in the macOS Keychain (`MacButler --set-key …` or Settings), not in `config.json`. They are sent only over https — plain http is allowed only to a server on this Mac. |
| Other programs sending commands | The control channel is a Unix socket in `~/.macbutler` (mode 0600) and every connection's user id is checked. Sandboxed apps and other users can't reach it. |
| A fake transcription server | Whisper runs on a random loopback port each launch and is only used while the process Mac Butler started is alive. |
| Tampered model download | `scripts/download-model.sh` verifies the SHA-256 published by Hugging Face. |
| Your data | Audio never leaves the Mac. `~/.macbutler` (settings, logs with what you said, socket) is owner-only; logs rotate at 5 MB. Only the text of commands that go to the brain you chose (Anthropic by default; nothing with a local model) and, if enabled, spoken answers (your paid voice) leave the Mac. |
| Tampered app | Releases are signed with Developer ID and notarized by Apple; SHA-256 is published with each release. CI uses pinned actions with read-only permissions. |

## Reporting a vulnerability

Please **do not open a public issue.** Use GitHub’s private reporting: *Security → Report a vulnerability* on this repository.
We aim to reply within 72 hours.
