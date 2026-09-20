#!/bin/bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_DIR/build/Today Calendar Prototype.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/dashboard/icons"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$REPO_DIR/build/swift-module-cache" \
  "$REPO_DIR/prototype/calendar/CalendarData.swift" \
  "$REPO_DIR/prototype/calendar/DashboardExtras.swift" \
  "$REPO_DIR/prototype/calendar/TodayCalendar.swift" \
  -o "$APP_DIR/Contents/MacOS/TodayCalendar"
cp "$REPO_DIR/app.js" "$REPO_DIR/styles.css" "$APP_DIR/Contents/Resources/dashboard/"
cp "$REPO_DIR/icons/"*.png "$APP_DIR/Contents/Resources/dashboard/icons/"
cp "$REPO_DIR/icons/Today.icns" "$APP_DIR/Contents/Resources/"
# Only public UI assets are bundled. Never copy data/ or the repository wholesale.
python3 - "$REPO_DIR" "$APP_DIR" <<'PY'
import pathlib, re, sys
repo, app = map(pathlib.Path, sys.argv[1:])
html = (repo / 'index.html').read_text()
html = re.sub(r'<link[^>]+rel="manifest"[^>]*>', '', html)
html = re.sub(r'<script src="data/[^\"]+"></script>', '', html)
html = html.replace('</head>', '''<style>
.bento-slack, .sticky-notes { display: none !important; }
.bento-comingup { grid-column: span 12; }
@media (max-width: 800px) { .bento-schedule, .bento-comingup { grid-column: span 12; } }
</style></head>''')
(app / 'Contents/Resources/dashboard/index.html').write_text(html)
PY
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.today-dashboard.calendar-prototype</string>
<key>CFBundleName</key><string>Today Calendar Prototype</string>
<key>CFBundleExecutable</key><string>TodayCalendar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleIconFile</key><string>Today.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Show local weather in Today. Only approximate coordinates are sent to the weather service.</string>
<key>NSLocationUsageDescription</key><string>Show local weather in Today using your approximate location.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Show events from calendars you select in your local Today dashboard. This prototype only reads events and does not upload them.</string>
</dict></plist>
PLIST
python3 - "$APP_DIR/Contents/Info.plist" "$REPO_DIR/data" <<'PYCONFIG'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info['TodayPersonalDataDirectory'] = sys.argv[2]
path.write_bytes(plistlib.dumps(info))
PYCONFIG
codesign --force --deep --sign - "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
