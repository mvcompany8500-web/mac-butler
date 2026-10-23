# Contributing

Thanks for helping! Mac Butler is a small, single-target Swift app — no Xcode project, no package manager.

```bash
./build.sh                                            # build/MacButler.app
build/MacButler.app/Contents/MacOS/MacButler --selftest # grammar tests, no mic needed
MACBUTLER_HOME=/tmp/mj open -n build/MacButler.app      # run with a throwaway settings folder
build/MacButler.app/Contents/Resources/bin/butler say "open chrome"   # talk to it in text
```

* **New quick command or language** → `Sources/MacButler/Commands.swift` (`Parser.parse`) + a case in `SelfTest.swift`.
* **Behaviour of the assistant** → `Resources/prompts/prompt.<lang>.md`.
* **UI** → `HUD.swift`, `BootScene.swift`.
* Keep it private by default: nothing new should leave the Mac without being explained in the README's *Privacy & safety*.
* Rebuilding with ad-hoc signing resets macOS permissions — set `SIGN_ID` in `local.env` to keep them while developing.

Please open an issue before large changes. By contributing you agree your work is released under the AGPL-3.0 license (and that MV Co., Ltd. may also offer it under other terms, e.g. in a commercial edition).
