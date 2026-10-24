#!/bin/zsh
# Removes the app and the login item. Keeps ~/.macbutler (settings, logs, model) unless you pass --all.
cd "${0:a:h}/.."
[[ -f local.env ]] && source local.env
APP_NAME=${APP_NAME:-Sasarisa}; BUNDLE_ID=${BUNDLE_ID:-com.macbutler.app}
launchctl bootout gui/$(id -u)/$BUNDLE_ID 2>/dev/null
rm -f ~/Library/LaunchAgents/$BUNDLE_ID.plist
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null
rm -rf ~/Applications/$APP_NAME.app ~/Applications/MacButler.app   # also the app before 0.7 (Mac Butler)
[[ "$1" == "--all" ]] && rm -rf ${MACBUTLER_HOME:-$HOME/.macbutler}
echo "✓ uninstalled"
