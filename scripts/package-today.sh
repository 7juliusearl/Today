#!/bin/bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$REPO_DIR/scripts/sign-today.py" preflight
TODAY_ARCHS="arm64 x86_64" "$REPO_DIR/scripts/build-calendar-prototype.sh"
TODAY_EXPORT=$(mktemp -d "$REPO_DIR/build/Today-Share-XXXXXX")
TODAY_FOLDER="$TODAY_EXPORT/Today"
mkdir -p "$TODAY_FOLDER/data" "$TODAY_FOLDER/custom"
cp -R "$REPO_DIR/build/Today.app" "$TODAY_FOLDER/Today.app"
cp -R "$REPO_DIR/build/Today.app/Contents/Resources/dashboard" "$TODAY_FOLDER/dashboard"
python3 - "$TODAY_FOLDER" <<'PY'
import pathlib, plistlib, sys, re, hashlib, json
root = pathlib.Path(sys.argv[1])
info = root / 'Today.app/Contents/Info.plist'
p = plistlib.loads(info.read_bytes())
p.pop('TodayPersonalDataDirectory', None)
p['TodayPortable'] = True
# Separate identity gives testers of the development app a clean first run too.
p['CFBundleIdentifier'] = 'com.today-dashboard.portable'
info.write_bytes(plistlib.dumps(p))
htmlpath = root / 'dashboard/index.html'
html = htmlpath.read_text().replace('Good morning,<br>Julius.', 'Welcome to Today.').replace('Created by Julius &middot; Made with love', 'Your day, in one place.')
html = re.sub(r'<div class="quicklinks-grid">.*?</div>\s*</section>', '<div class="quicklinks-grid"><p class="empty-state">Choose Edit links to add your shortcuts.</p></div>\n  </section>', html, flags=re.S)
html = html.replace('<html lang="en">', '<html lang="en" data-edition="coworker">')
htmlpath.write_text(html)
(root/'Today.app/Contents/Resources/dashboard/index.html').write_text(html)
(root/'data/schedule.js').write_text('// Weekly rhythm is not included in the coworker edition.\nwindow.WORK_SCHEDULE = null;\n')
(root/'data/plan.js').write_text('// Personal onboarding plans are not included in the coworker edition.\nwindow.ONBOARDING_PLAN = null;\n')
(root/'TODAY-PROJECT.txt').write_text('Today portable project — keep Today.app, dashboard, and data together.\n')
(root/'custom/user.css').write_text('/* Personal style overrides. These are kept when Today updates. */\n')
(root/'custom/user.js').write_text('// Personal behavior and shortcuts. This file is kept when Today updates.\n// Run changes once here; use window.addEventListener("today:updated", ...) after refreshes.\n')
baseline = {'version': p['CFBundleShortVersionString'], 'build': int(p['CFBundleVersion']), 'dashboard': {str(f.relative_to(root/'dashboard')): hashlib.sha256(f.read_bytes()).hexdigest() for f in (root/'dashboard').rglob('*') if f.is_file() and f.name != '.DS_Store'}}
(root/'.today-release.json').write_text(json.dumps(baseline, indent=2)+'\n')
PY
cp "$REPO_DIR/prototype/calendar/portable/START-HERE.md" "$TODAY_FOLDER/START-HERE.md"
cp "$REPO_DIR/prototype/calendar/portable/AGENTS.md" "$TODAY_FOLDER/AGENTS.md"
cp "$REPO_DIR/prototype/calendar/portable/AGENTS.md" "$TODAY_FOLDER/CLAUDE.md"
cp "$REPO_DIR/prototype/calendar/portable/UPDATES.md" "$TODAY_FOLDER/UPDATES.md"
cp "$REPO_DIR/prototype/calendar/portable/Update Existing Today.command" "$TODAY_FOLDER/Update Existing Today.command"
chmod +x "$TODAY_FOLDER/Update Existing Today.command"
python3 "$REPO_DIR/scripts/sign-today.py" release-sign "$TODAY_FOLDER/Today.app"
python3 "$REPO_DIR/scripts/sign-today.py" notarize "$TODAY_FOLDER/Today.app"
ditto -c -k --keepParent "$TODAY_FOLDER" "$TODAY_EXPORT/Today.zip"
printf 'Share this archive: %s\nProject folder: %s\n' "$TODAY_EXPORT/Today.zip" "$TODAY_FOLDER"
