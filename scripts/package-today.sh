#!/bin/bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TODAY_ARCHS="arm64 x86_64" "$REPO_DIR/scripts/build-calendar-prototype.sh"
TODAY_EXPORT=$(mktemp -d "$REPO_DIR/build/Today-Share-XXXXXX")
TODAY_FOLDER="$TODAY_EXPORT/Today"
mkdir -p "$TODAY_FOLDER/data" "$TODAY_FOLDER/examples"
cp -R "$REPO_DIR/build/Today.app" "$TODAY_FOLDER/Today.app"
cp -R "$REPO_DIR/build/Today.app/Contents/Resources/dashboard" "$TODAY_FOLDER/dashboard"
cp "$REPO_DIR/data/schedule.example.js" "$REPO_DIR/data/plan.example.js" "$TODAY_FOLDER/examples/"
python3 - "$TODAY_FOLDER" <<'PY'
import pathlib, plistlib, sys, re
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
html = re.sub(r'<div class="quicklinks-grid">.*?</div>\s*</section>', '<div class="quicklinks-grid"><p class="empty-state">Add your shortcuts with Codex or Claude.</p></div>\n  </section>', html, flags=re.S)
htmlpath.write_text(html)
(root/'Today.app/Contents/Resources/dashboard/index.html').write_text(html)
(root/'data/schedule.js').write_text('// Personal weekly rhythm. Ask Codex or Claude to customize this.\nwindow.WORK_SCHEDULE = null;\n')
(root/'data/plan.js').write_text('// Personal goals or onboarding plan. Start from examples/plan.example.js.\nwindow.ONBOARDING_PLAN = null;\n')
(root/'TODAY-PROJECT.txt').write_text('Today portable project — keep Today.app, dashboard, and data together.\n')
PY
cp "$REPO_DIR/prototype/calendar/portable/START-HERE.md" "$TODAY_FOLDER/START-HERE.md"
cp "$REPO_DIR/prototype/calendar/portable/AGENTS.md" "$TODAY_FOLDER/AGENTS.md"
cp "$REPO_DIR/prototype/calendar/portable/AGENTS.md" "$TODAY_FOLDER/CLAUDE.md"
codesign --force --deep --sign "${TODAY_SIGNING_IDENTITY:--}" "$TODAY_FOLDER/Today.app"
codesign --verify --deep --strict "$TODAY_FOLDER/Today.app"
ditto -c -k --keepParent "$TODAY_FOLDER" "$TODAY_EXPORT/Today.zip"
printf 'Share this archive: %s\nProject folder: %s\n' "$TODAY_EXPORT/Today.zip" "$TODAY_FOLDER"
