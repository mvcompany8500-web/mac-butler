#!/bin/zsh
# One-shot install: deps → model → build → ~/Applications → start at login.
#   ./scripts/install.sh            full install
#   ./scripts/install.sh --no-model skip the 874 MB Whisper download (uses Apple speech only)
set -e
cd "${0:a:h}/.."
[[ -f local.env ]] && source local.env
APP_NAME=${APP_NAME:-Sasarisa}; BUNDLE_ID=${BUNDLE_ID:-com.macbutler.app}
HOME_DIR=${MACBUTLER_HOME:-$HOME/.macbutler}

say_step() { print -P "%F{cyan}›%f $1"; }

say_step "checking tools"
command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh"; exit 1; }
for f in whisper-cpp cliclick; do brew list $f >/dev/null 2>&1 || brew install $f; done
if ! command -v claude >/dev/null && [[ ! -x ~/.claude/local/claude ]]; then
  echo "⚠︎ Claude Code not found. Install it (https://docs.claude.com/en/docs/claude-code) and run \`claude\` once to log in."
fi

if [[ "$1" != "--no-model" ]]; then ./scripts/download-model.sh; fi

say_step "building"
./build.sh
mkdir -p ~/Applications
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf ~/Applications/$APP_NAME.app && cp -R build/$APP_NAME.app ~/Applications/
if [[ "$APP_NAME" != MacButler ]]; then pkill -f "MacButler.app/Contents/MacOS/MacButler" 2>/dev/null; rm -rf ~/Applications/MacButler.app; fi   # the app before 0.7 (Mac Butler)

say_step "starting at login (LaunchAgent $BUNDLE_ID)"
PL=~/Library/LaunchAgents/$BUNDLE_ID.plist
launchctl bootout gui/$(id -u)/$BUNDLE_ID 2>/dev/null || true
for i in {1..20}; do launchctl print gui/$(id -u)/$BUNDLE_ID >/dev/null 2>&1 || break; sleep 0.5; done
cat > $PL <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$BUNDLE_ID</string>
<key>ProgramArguments</key><array><string>$HOME/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>10</integer>
</dict></plist>
PLIST
launchctl bootstrap gui/$(id -u) $PL || { sleep 2; launchctl bootstrap gui/$(id -u) $PL; }

echo
echo "✓ Installed. Say 「사사리사」 or “hey Sasarisa” — look for it in the menu bar."
echo "  First run: allow Microphone, Speech Recognition, Accessibility and Screen Recording."
echo "  Settings: $HOME_DIR/config.json   ·   Logs: $HOME_DIR/logs/butler.log"
