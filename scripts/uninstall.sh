#!/bin/zsh
# Removes the app and the login item. Keeps ~/.myjarvis (settings, logs, model) unless you pass --all.
cd "${0:a:h}/.."
[[ -f local.env ]] && source local.env
APP_NAME=${APP_NAME:-MyJarvis}; BUNDLE_ID=${BUNDLE_ID:-com.myjarvis.app}
launchctl bootout gui/$(id -u)/$BUNDLE_ID 2>/dev/null
rm -f ~/Library/LaunchAgents/$BUNDLE_ID.plist
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null
rm -rf ~/Applications/$APP_NAME.app
[[ "$1" == "--all" ]] && rm -rf ${MYJARVIS_HOME:-$HOME/.myjarvis}
echo "✓ uninstalled"
