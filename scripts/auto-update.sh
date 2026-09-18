#!/bin/bash
# Pulls the latest code from the shared repo so everyone's dashboard stays
# current without manual `git pull`s. Combined with app.js's 10-minute
# auto-reload, a push to GitHub reaches open dashboards within ~40 minutes
# by default (StartInterval below + the reload).
#
# Safety: --ff-only means this can only ever fast-forward. It never creates
# a merge commit and never touches uncommitted local changes — if you've
# customized styles.css/etc. and that conflicts with an incoming change,
# git just refuses the pull and this script logs it, leaving your working
# tree exactly as it was. Your personal data files (data/dashboard.js,
# schedule.js, plan.js) are gitignored and were never affected either way.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

echo "[$(date)] Checking for updates..."
git fetch origin main --quiet
if git pull --ff-only origin main; then
  echo "[$(date)] Up to date."
else
  echo "[$(date)] Could not fast-forward — likely local changes conflict with an incoming update. Left untouched; pull manually to resolve."
fi
