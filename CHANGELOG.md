# Changelog

## 0.6.3 — 2026-10-23
- The orb & card now sit in the bottom-right corner by default (out of the way of what you're doing); bottom-left / top in Settings → Basics

## 0.6.2 — 2026-10-23
- Fix: breathing into the mic stopped it mid-answer. Cutting in now also needs a voice-like pitch (breath, a bump or a puff on the mic don't have one) — checked on 1,391 chunks of real speech vs. noise

## 0.6.1 — 2026-10-23
- Fix: the first word went missing when the live recognizer split a sentence (「하이 자비스 / 아멜리아 먹방…」 → 「먹방…」)
- Whisper output that heard a video or other people (dialogue lines, far longer than what you said) falls back to the live text
- Cutting in over speakers is stricter (someone else talking or a video won't cut it off); the wake word / hotkey always works
- A stray word from someone in the room no longer cancels what Claude is doing; corrections (「아니 …」) aren't learned as commands
- New: 「화면 꺼」 (display off), 「다음 영상」 (⏭), 「유튜브 화면 꺼」 closes those tabs, 「켜져 있는 클로드에게」 = current window

## 0.6.0 — 2026-10-23
- **Works out of the box with the built-in macOS voice** — free, offline; picks the most natural installed voice (Premium > Enhanced > Yuna/Samantha). Setup shows how to get a free Premium voice. ElevenLabs stays optional (the demo video's voice)
- **Cut in over speakers** — no headphones needed: it compares the mic with how loud it is talking, and ignores a video playing in the room (`--echotest` checks your room)
- **Korean read aloud correctly** — 「3시 16분」→「세 시 십육 분」, 「10월」→「시월」, 「M4」→「엠포」, money, units
- **Video control:** 「영상 멈춰」, 「유튜브 꺼」, 「다시 틀어」 (⏯, only when something is playing); 「유튜브 창 꺼」 closes those tabs; after a video starts it stops listening so the video isn't taken as commands
- **Commands:** 「유튜브에 ○○ 검색해서 재생시켜」, lead-ins like 「알았어. 그러면」 dropped, 「쿠팡의/쿠팡이 …」, 「띄워서」, a follow-up search stays on the same shop, 「지금 떠 있는 클로드 창」, misheard wake words (「하이 재비스」)
- **Recognition:** utterance audio no longer cut by a click after you finish; Whisper's shaky words and repeated made-up tails fall back to the live text; YouTube = 유튜브 when comparing; optional `keepAudio` keeps the last 30 utterances locally for tuning
- Remembers past conversations (`memory.md` + recent log); shorter spoken answers (one sentence)
- On-screen orb & card can sit top / bottom-right / bottom-left (Settings → Basics)

## 0.5.1 — 2026-10-23
- Fix: the mic could get stuck restarting after audio changes (stopped hearing the wake word) — now restarts only when it really stopped, with a fresh engine and a 3 s debounce; recognizer stall detection
- Choose microphone and speaker in Settings (`--devices` lists them)
- Claude sees both transcripts when Whisper and live recognition disagree; quick commands fall back to the live text
- Grows: missed words are studied into the vocabulary; stale learned commands and temp files are swept; progress in the menu

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
