#!/bin/bash
# Adds Claude Code to macOS Login Items, so it launches automatically at
# login. This matters because the dashboard's scheduled data refresh only
# fires while the Claude Code desktop app is open — the server/site itself
# doesn't need it, but the calendar/Slack/sticky-note refresh does.
#
# Safe to re-run: checks whether Claude is already a login item before
# adding it. Reversible any time via System Settings -> General -> Login
# Items (or: osascript -e 'tell application "System Events" to delete login item "Claude"').
set -euo pipefail

APP_PATH="/Applications/Claude.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Claude.app not found at $APP_PATH — skipping (is it installed elsewhere?)."
  exit 0
fi

EXISTING="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")"

if echo "$EXISTING" | grep -qi "claude"; then
  echo "Claude is already a login item — nothing to do."
else
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_PATH\", hidden:false}"
  echo "Added Claude to Login Items. It will now launch automatically at login."
fi
