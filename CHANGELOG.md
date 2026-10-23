# Changelog

## 0.5.0 — 2026-10-23
- **Push-to-talk:** hold right ⌥ and talk, release to run (exact audio, like Handy); tap still wakes. New `activation: "hold"` = hotkey only, nothing transcribed otherwise
- **Setup window** on first launch: live permission checklist, one-click fixes, in-app Whisper download with SHA-256 check
- **Learns:** steps Claude found once are replayed instantly next time (no Claude call); “아니/no” right after = don't learn; menu shows today's calls/tokens and can forget everything
- **Interrupt anytime:** a new command while Claude works replaces the old one; trailing 「아니 취소」 cancels; 0.8 s cancel window before sending to Claude; pasting instead of slow typing
- **Recognition:** mic restarts automatically after audio changes (the “stops responding after a while” bug), VAD utterance start, Whisper hallucination/unrelated-text filter, Handy vocabulary import, filler removal
- **12 languages:** ko, en, ja, zh, es, fr, de, pt, it, vi, th, id (Claude answers in your language); defaults to the Mac's language
- Spoken Claude hand-offs go straight through; confirmation only when the assistant proposes one; 「지금 켜진 클로드 창에」 targets the current session; `butler session`

## 0.4.0 — 2026-10-23 · security hardening
- **Safe mode (default):** Claude gets a fixed tool allowlist — no arbitrary shell, file writes, URL fetching or MCP; user Claude settings aren't loaded (`brainAccess: "full"` to opt out)
- `jax`/`jtype` refuse to press/type/click in terminals, code editors, Claude, System Settings, Keychain, password managers and permission prompts; `jax open-app`, `open-url` (http/s only), `screenshot`, `click`, `key`, `volume`, `front`
- Handing a task to Claude Code asks for a spoken yes first (`confirmDelegate`)
- Commands from tools go over an owner-only Unix socket with peer-uid check (replaces public distributed notifications)
- Whisper on a random loopback port, used only while our own process is alive; pid-file cleanup
- `~/.macbutler` is 0700, logs 0600 and rotated at 5 MB
- Model download verifies SHA-256; CI pinned + read-only; SECURITY.md
- Shopping & site search: 쿠팡 / 네이버 쇼핑 / 네이버 / 구글 / 아마존, 「○○ 최저가」
- Releases signed with Developer ID and notarized

## 0.3.0 — 2026-10-23
- Settings window (menu → Settings…, ⌘,): language, name, wake words, voice, hotkey, Claude model — saves to config.json (other keys kept) and restarts
- `butler settings` opens it from the command line
- Boot log title keeps word spacing (“MAC BUTLER · BOOT SEQUENCE”)

## 0.2.0 — 2026-10-23
- Renamed **My Jarvis → Mac Butler** (repo `mac-butler`, app `MacButler.app`, settings `~/.macbutler`, CLI `butler`).
  The assistant still answers to “Jarvis” by default; `~/.myjarvis` is moved automatically on first launch.
- README: demo GIF, one-line install, Homebrew tap, CI badge; non-affiliation notice
- CI: build + `--selftest` on every push

## 0.1.0 — 2026-10-23
First public version.
- Always-on wake word (Apple on-device speech) + Whisper large-v3-turbo for accurate text
- Warm Claude Code brain (stream-json), answers spoken via macOS `say` or ElevenLabs
- Quick commands (ko/en): open apps, web search, YouTube play / “the second one”, type, dictation
- Hand tasks to a new Claude Code session in the Claude app — by Accessibility, no mouse movement
- Barge-in, conversation mode, right-⌥ hotkey, status/permission checklist in the menu
- Wake-up animation, HUD orb, `--selftest`
