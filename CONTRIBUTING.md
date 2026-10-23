# Contributing

Thanks for helping! My Jarvis is a small, single-target Swift app — no Xcode project, no package manager.

```bash
./build.sh                                            # build/MyJarvis.app
build/MyJarvis.app/Contents/MacOS/MyJarvis --selftest # grammar tests, no mic needed
MYJARVIS_HOME=/tmp/mj open -n build/MyJarvis.app      # run with a throwaway settings folder
build/MyJarvis.app/Contents/Resources/bin/jarvis-ping say "open chrome"   # talk to it in text
```

* **New quick command or language** → `Sources/MyJarvis/Commands.swift` (`Parser.parse`) + a case in `SelfTest.swift`.
* **Behaviour of the assistant** → `Resources/prompts/prompt.<lang>.md`.
* **UI** → `HUD.swift`, `BootScene.swift`.
* Keep it private by default: nothing new should leave the Mac without being explained in the README's *Privacy & safety*.
* Rebuilding with ad-hoc signing resets macOS permissions — set `SIGN_ID` in `local.env` to keep them while developing.

Please open an issue before large changes. By contributing you agree your work is released under the MIT license.
