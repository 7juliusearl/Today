#!/bin/bash
# Builds a real macOS .app wrapper for the dashboard and pins it to the Dock.
# Safari/Chrome's "Add to Dock" can't be scripted (it's a manual browser-menu
# action), but a genuine .app bundle can be built and added to the Dock
# programmatically — this does that instead, with the same custom icon.
#
# Safety: this script only ever ADDS to the Dock (defaults ... -array-add),
# and only ever CREATES files — it never deletes or rewrites Dock entries or
# app bundles. If something with the same name already exists (e.g. you
# already used Safari's "Add to Dock" yourself), it leaves that alone and
# just makes sure something with this name is pinned.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Today"
APP_DIR="$HOME/Applications/$APP_NAME.app"

mkdir -p "$HOME/Applications"

if [ -e "$APP_DIR" ]; then
  echo "$APP_DIR already exists — leaving it as-is (not rebuilding)."
else
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.today-dashboard.app</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSUIElement</key>
	<false/>
</dict>
</plist>
PLIST

  cp "$REPO_DIR/icons/Today.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

  cat > "$APP_DIR/Contents/MacOS/$APP_NAME" <<'LAUNCHER'
#!/bin/bash
# Opens the dashboard as a chrome-less window if Chrome is installed,
# otherwise falls back to a normal tab in the default browser.
URL="http://localhost:4173"
if [ -d "/Applications/Google Chrome.app" ]; then
  open -na "Google Chrome" --args --new-window --app="$URL"
else
  open "$URL"
fi
LAUNCHER
  chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
  touch "$APP_DIR"
  echo "Built $APP_DIR"
fi

# Add to the Dock if something at this exact path isn't already pinned.
# Read-only check first; the write is a pure append, never a rewrite.
if defaults read com.apple.dock persistent-apps 2>/dev/null | grep -qF "$APP_DIR"; then
  echo "$APP_NAME is already pinned to the Dock — nothing more to do."
else
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_DIR/</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock >/dev/null 2>&1 || true
  echo "Pinned $APP_NAME to the Dock."
fi
