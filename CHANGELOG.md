# Changelog

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
