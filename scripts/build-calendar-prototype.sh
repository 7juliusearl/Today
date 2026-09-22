#!/bin/bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_DIR/build/Today.app"
# Replacing a running executable can leave TCC checking the previous signature.
if pgrep -x TodayCalendar >/dev/null; then
  echo "Quit Today before rebuilding so its running signature matches the installed app." >&2
  exit 1
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/dashboard/icons"
for today_arch in ${TODAY_ARCHS:-$(uname -m)}; do
xcrun swiftc -parse-as-library -target "$today_arch-apple-macosx14.0" \
  -module-cache-path "$REPO_DIR/build/swift-module-cache" \
  "$REPO_DIR/prototype/calendar/CalendarData.swift" \
  "$REPO_DIR/prototype/calendar/DashboardExtras.swift" \
  "$REPO_DIR/prototype/calendar/AppLifecycle.swift" \
  "$REPO_DIR/prototype/calendar/WindowSpace.swift" \
  "$REPO_DIR/prototype/calendar/MailData.swift" \
  "$REPO_DIR/prototype/calendar/TodayPaths.swift" \
  "$REPO_DIR/prototype/calendar/UpdateSupport.swift" \
  "$REPO_DIR/prototype/calendar/TodayUpdater.swift" \
  "$REPO_DIR/prototype/calendar/IntroView.swift" \
  "$REPO_DIR/prototype/calendar/Companion.swift" \
  "$REPO_DIR/prototype/calendar/TodayCalendar.swift" \
  -o "$REPO_DIR/build/TodayCalendar-$today_arch"
xcrun swiftc -parse-as-library -target "$today_arch-apple-macosx14.0" \
  -module-cache-path "$REPO_DIR/build/swift-module-cache" \
  "$REPO_DIR/prototype/calendar/UpdateSupport.swift" \
  "$REPO_DIR/prototype/calendar/TodayUpdateHelper.swift" \
  -o "$REPO_DIR/build/TodayUpdateHelper-$today_arch"
done
today_binaries=()
for today_arch in ${TODAY_ARCHS:-$(uname -m)}; do today_binaries+=("$REPO_DIR/build/TodayCalendar-$today_arch"); done
xcrun lipo -create "${today_binaries[@]}" -output "$APP_DIR/Contents/MacOS/TodayCalendar"
today_helpers=()
for today_arch in ${TODAY_ARCHS:-$(uname -m)}; do today_helpers+=("$REPO_DIR/build/TodayUpdateHelper-$today_arch"); done
xcrun lipo -create "${today_helpers[@]}" -output "$APP_DIR/Contents/MacOS/TodayUpdateHelper"
cp "$REPO_DIR/prototype/calendar/companion/"* "$APP_DIR/Contents/Resources/"
cp "$REPO_DIR/app.js" "$REPO_DIR/styles.css" "$APP_DIR/Contents/Resources/dashboard/"
cp "$REPO_DIR/prototype/calendar/overview.css" "$APP_DIR/Contents/Resources/dashboard/"
cp "$REPO_DIR/icons/"*.png "$APP_DIR/Contents/Resources/dashboard/icons/"
cp "$REPO_DIR/prototype/calendar/authorize-calendar.js" "$APP_DIR/Contents/Resources/"
cp "$REPO_DIR/prototype/calendar/open-calendar.js" "$APP_DIR/Contents/Resources/"
cp "$REPO_DIR/prototype/calendar/mail/read-mail.js" "$APP_DIR/Contents/Resources/"
cp "$REPO_DIR/icons/Today.icns" "$APP_DIR/Contents/Resources/"
# Only public UI assets are bundled. Never copy data/ or the repository wholesale.
python3 - "$REPO_DIR" "$APP_DIR" <<'PY'
import pathlib, re, sys
repo, app = map(pathlib.Path, sys.argv[1:])
html = (repo / 'index.html').read_text()
html = re.sub(r'<link[^>]+rel="manifest"[^>]*>', '', html)
html = re.sub(r'<script src="data/[^\"]+"></script>', '', html)
html = html.replace('</body>', '<script src="../custom/user.js"></script></body>')
html = html.replace('<div class="glass-card bento-comingup"', '''<div class="glass-card bento-mail">
  <div class="panel-head mail-header"><div><p class="eyebrow">Apple Mail</p><h2 class="panel-title" id="mail-title">Inbox</h2></div>
    <button type="button" class="mail-open-app" id="mail-open-app">Open Mail ↗</button>
  </div>
  <div class="panel-body" id="mail-list"></div>
</div>
<div class="glass-card bento-comingup"''')
html = html.replace('</head>',  '''<style>
.bento-slack, .sticky-notes { display: none !important; }
.bento-mail, .bento-comingup { grid-column: span 6; }
.bento-mail { padding: 30px; }
.mail-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; }
.mail-open-app { font: inherit; font-size: 12px; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; }
.mail-open-app { white-space: nowrap; opacity: .6; margin-top: 3px; }
.mail-open-app:hover { opacity: 1; color: #ed4b20; text-decoration: underline; }
#mail-list { max-height: none; overflow: visible; min-width: 0; gap: 0; }
.mail-status { font-size: 11px; line-height: 1.5; opacity: .55; margin: 0 0 12px; overflow-wrap: anywhere; }
.mail-item { display: grid; grid-template-columns: minmax(0, 1fr) auto; column-gap: 10px; row-gap: 4px; padding: 12px 0; cursor: pointer; width: 100%; text-align: left; font: inherit; color: inherit; background: none; border: 0; border-bottom: 1px solid #8883; min-width: 0; }
.mail-item:last-child { border-bottom: 0; }
.mail-item:hover .mail-sender { color: var(--accent); }
.mail-item:disabled { opacity: .5; cursor: default; }
.mail-item-unread { position: relative; isolation: isolate; }
.mail-item-unread::before, .mail-item-unread::after { content: ''; position: absolute; inset: 3px -10px; border-radius: 10px; pointer-events: none; z-index: -1; }
.mail-item-unread::before { background: linear-gradient(120deg, var(--accent), var(--accent-2) 55%, transparent); opacity: .045; }
.mail-item-unread::after { padding: 1px; background: linear-gradient(120deg, var(--accent), var(--accent-2) 55%, transparent); opacity: .18; -webkit-mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0); -webkit-mask-composite: xor; mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0); mask-composite: exclude; }
.mail-sender { grid-column: 1; font-family: var(--sans); font-size: 17px; line-height: 1.3; font-weight: 700; color: var(--ink); overflow-wrap: anywhere; }
.mail-item-read .mail-sender { font-weight: 500; }
.mail-read-status { display: inline-flex; align-items: center; gap: 5px; margin-left: 8px; vertical-align: middle; font-size: 10px; line-height: 1.4; font-weight: 500; color: var(--ink-soft); white-space: nowrap; }
.mail-item-unread .mail-read-status::before { content: ''; width: 6px; height: 6px; border-radius: 50%; background: #409cff; flex-shrink: 0; }
.mail-time { grid-column: 2; font-size: 11px; opacity: .55; white-space: nowrap; }
.mail-subject { grid-column: 1 / 3; grid-row: 2; font-size: 12px; line-height: 1.5; font-weight: 400; color: var(--ink-soft); overflow-wrap: anywhere; }
.mail-attachments { grid-column: 1 / 3; font-size: 11px; opacity: .55; }
.mail-item:focus-visible, .mail-open-app:focus-visible { outline: 2px solid #ed4b20; outline-offset: 4px; }
@media (max-width: 800px) { .bento-schedule, .bento-mail, .bento-comingup { grid-column: span 12; } }
</style><link rel="stylesheet" href="overview.css" /></head>''')
html = html.replace('</head>', '<link rel="stylesheet" href="../custom/user.css" /></head>')
(app / 'Contents/Resources/dashboard/index.html').write_text(html)
PY
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.today-dashboard.calendar-prototype</string>
<key>CFBundleName</key><string>Today</string>
<key>CFBundleDisplayName</key><string>Today</string>
<key>CFBundleExecutable</key><string>TodayCalendar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleIconFile</key><string>Today.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppleEventsUsageDescription</key><string>Read today’s message headers from the mailbox you choose in Apple Mail and open messages when you click them. Also reveal selected invitations in Calendar so you can respond there. Today does not submit responses or change messages.</string>
<key>NSLocalNetworkUsageDescription</key><string>Share your Today dashboard with an iPad on your local network when you enable companion sharing.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Show local weather in Today. Only approximate coordinates are sent to the weather service.</string>
<key>NSLocationUsageDescription</key><string>Show local weather in Today using your approximate location.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Show events from calendars you select in your local Today dashboard. This prototype only reads events and does not upload them.</string>
</dict></plist>
PLIST
python3 - "$APP_DIR/Contents/Info.plist" "$REPO_DIR/data" "$REPO_DIR" <<'PYCONFIG'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info['TodayPersonalDataDirectory'] = sys.argv[2]
repo = pathlib.Path(sys.argv[3])
release = __import__('json').loads((repo/'release.json').read_text())
info['CFBundleShortVersionString'] = release['version']
info['CFBundleVersion'] = str(release['build'])
info['TodayUpdateFeedURL'] = release.get('feedURL', '')
info['TodayUpdatePublicKey'] = (repo/'update-public-key.txt').read_text().strip()
path.write_bytes(plistlib.dumps(info))
PYCONFIG
mkdir -p "$APP_DIR/Contents/Resources/custom"
touch "$APP_DIR/Contents/Resources/custom/user.css" "$APP_DIR/Contents/Resources/custom/user.js"
codesign --force --sign "${TODAY_SIGNING_IDENTITY:--}" "$APP_DIR/Contents/MacOS/TodayUpdateHelper"
codesign --force --deep --sign "${TODAY_SIGNING_IDENTITY:--}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
if [ "${TODAY_SIGNING_IDENTITY:--}" = "-" ]; then
  echo "Development signing: macOS permissions may need re-adding after this rebuild. Set TODAY_SIGNING_IDENTITY to a stable signing certificate to preserve identity."
fi
printf 'Built: %s\n' "$APP_DIR"
