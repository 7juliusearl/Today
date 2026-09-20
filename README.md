# Today

A personal "command center" dashboard: today's calendar (including a shared team calendar), unread-ish Slack activity, a verse of the day, live weather, and your own weekly work rhythm / onboarding plan if you set them up. Runs entirely locally as a static site, refreshed throughout the work day by a Claude Code scheduled task (plus an on-demand check within ~2 minutes of hitting the Refresh button).

Dark glass, rounded bento cards, a warm orange accent — designed to feel like a native macOS panel rather than a webpage.

## Features

- **Today's Schedule** — merges your personal Google Calendar with a shared team calendar, click any event to expand attendees, RSVP status, description, and meeting/calendar links
- **Coming Up** — the next few days with something on them, when today's clear
- **Needs Your RSVP** — every calendar invite you haven't responded to yet, regardless of how far out it is
- **Slack** — messages posted since the dashboard's last refresh (there's no true "unread" API, so this is the closest honest equivalent)
- **Sticky notes** — a coworker can leave you an encouraging note by DMing you on Slack starting with 📌 (or `:pushpin:` / `note:` if the emoji doesn't come through); it shows up as an actual rotated sticky note stuck to a corner of the page. Up to 3 can be stuck up at once from different people, each in its own spot — dismissible, sticks around ~2 weeks or until whoever sent it sends a newer one
- **Verse of the Day** — pulled from a public verse API each morning
- **Weather** — live, via your browser's location, no API key needed
- **Work Schedule / Onboarding** *(optional)* — your own hand-maintained weekly rhythm and 30/60/90 plan, if you fill them in
- Light/dark toggle, a custom Dock icon, and a refresh button that requests a real live data pull within ~2 minutes (not just a page reload — see "How refreshing works" below)

## Setting this up for yourself

This dashboard is driven by [Claude Code](https://claude.com/claude-code) — a scheduled task does the data fetching (it needs access to your Google Calendar and, optionally, Slack), and everything else is a static site with no server-side code of its own.

**The short version:**

1. Install [Claude Code](https://claude.com/claude-code) if you don't already have it.
2. Clone this repo: `git clone https://github.com/7juliusearl/Today.git && cd Today`
3. Open this folder in Claude Code and say **"set up my dashboard"** (or run `/setup-dashboard`).

That's it — Claude walks you through connecting your calendar (and Slack, if you want it), creates your personal refresh schedule, pulls in real data immediately, and gets the local server running, using the [setup-dashboard skill](.claude/skills/setup-dashboard/SKILL.md) bundled in this repo. On macOS it also sets up the always-on background server and pins a real Dock icon automatically — nothing to click through in a browser menu.

**One important thing it tells you up front**: the data refresh only happens while the Claude Code desktop app is open — the dashboard itself works fine without it, but nothing new gets fetched until Claude Code is running again. The setup flow will offer to add Claude Code to your macOS Login Items (asking first) so this stops being something you have to think about.

<details>
<summary>Prefer to do it by hand instead?</summary>

1. **Connect your calendar (and optionally Slack)** to Claude Code — connectors settings.
2. **Copy `data/dashboard.example.js` to `data/dashboard.js`** so the page has something to show before your first refresh runs.
3. **Create a scheduled task** (`refresh-dashboard-data`) that regenerates `data/dashboard.js` on whatever cadence you want during the work day (e.g. every 30 min, 8am–5pm weekdays) — the [setup-dashboard skill](.claude/skills/setup-dashboard/SKILL.md) contains the exact task design (including some non-obvious lessons learned, like Slack having no real unread API). Point Claude at that file and have it build the same task manually. The page auto-reloads itself every 10 minutes, so an already-open tab picks up each refresh without anyone clicking anything.
3b. **(Optional) Create the on-demand checker** (`refresh-dashboard-on-demand`) so the Refresh button does a real live pull within ~2 min instead of just reloading a stale file — see "How refreshing works" below and the skill file for the exact task design.
4. **Run it once**, then `./start.sh` to open `http://localhost:4173` in your regular browser (not Claude's built-in one — no logins there).
5. **(Optional)** Copy `com.today-dashboard.plist.example` to `~/Library/LaunchAgents/com.today-dashboard.plist`, fix the path inside it, then `launchctl load -w ~/Library/LaunchAgents/com.today-dashboard.plist` to keep it running permanently.
6. **(Optional)** Same for `com.today-dashboard-autoupdate.plist.example` → `com.today-dashboard-autoupdate.plist`, to pull code updates from GitHub automatically every 30 minutes (`git pull --ff-only` — never overwrites local changes, just skips a conflicting update and logs it).
7. **(Optional)** Dock icon: run `./scripts/install-dock-app.sh` (macOS, builds a real `.app` and pins it — safe to re-run), or do it manually via Safari → File → Add to Dock / Chrome's install-as-app.

</details>

## Customizing

- **Colors** — CSS variables at the top of `styles.css` (`--bg`, `--ink`, `--accent`, etc.), separate blocks for light and dark mode
- **Icon** — `icons/source.svg` is the editable source; regenerate PNGs with `qlmanage -t -s <size> -o icons icons/source.svg` (macOS QuickLook, no extra tools needed)
- **Layout** — the bento grid is plain CSS Grid in `styles.css` (`.bento-*` classes); add/remove/reorder cards in `index.html`

## Managing the background server

```bash
launchctl unload ~/Library/LaunchAgents/com.today-dashboard.plist   # stop
launchctl load -w ~/Library/LaunchAgents/com.today-dashboard.plist  # start again
tail -f /tmp/today-dashboard.log /tmp/today-dashboard-error.log     # logs
```

Note: the scheduled task itself only fires while the Claude Code desktop app is open — if it's closed at refresh time, it runs on next launch instead.

## How refreshing works

Three layers, working together:

1. **Scheduled task** (`refresh-dashboard-data`) — the real Calendar/Slack/verse fetch, on whatever cadence you picked during setup (e.g. every 30 min, 8am–5pm weekdays).
2. **Auto-reload** — the page itself reloads every 10 minutes, so an already-open tab picks up each scheduled refresh with no clicking.
3. **The Refresh button** — clicking it does two things: reloads immediately (showing whatever's currently on disk, same as before), and calls a small `/api/refresh` endpoint on the local server, which sets a flag. A second, lightweight scheduled task (`refresh-dashboard-on-demand`) checks for that flag every 2 minutes and, only when it's present, does a full real refresh immediately rather than waiting for the next scheduled slot. Most checks find nothing and cost almost nothing — the expensive work only happens when someone actually clicks Refresh.

Net effect: clicking Refresh gets you real fresh data within about 2 minutes, not instantly (a browser button genuinely can't call Claude Code's tools directly — there's no bridge for that), but far better than waiting for the next 30-minute slot.

## Staying up to date

If the auto-update LaunchAgent is set up (see setup steps above), code changes pushed to this repo reach every clone within about 30–40 minutes automatically — no `git pull` needed. It's a plain `--ff-only` pull, so it can only ever fast-forward: it never force-overwrites anything, never touches your gitignored personal data, and if you've hand-edited a tracked file (like tweaking a color in `styles.css`) in a way that conflicts with an incoming change, it just skips that pull and logs it rather than clobbering your edit.

```bash
launchctl unload ~/Library/LaunchAgents/com.today-dashboard-autoupdate.plist   # stop
launchctl load -w ~/Library/LaunchAgents/com.today-dashboard-autoupdate.plist  # start again
tail -f /tmp/today-dashboard-autoupdate.log                                   # logs
git pull                                                                      # do it manually, any time
```

## Files

- `index.html` / `styles.css` / `app.js` — the page
- `data/*.example.js` — the schema each optional data file expects; copy to the non-`.example` name and fill in
- `data/dashboard.js`, `data/schedule.js`, `data/plan.js` — your real, gitignored personal data
- `icons/` — app icon source (`source.svg`), generated PNGs, and `Today.icns` for the Dock app; `manifest.json` — PWA metadata
- `start.sh` — local server launcher
- `scripts/server.py` — the local server (static files + the `/api/refresh` endpoint the Refresh button uses)
- `scripts/install-dock-app.sh` — builds and pins the Dock icon (macOS, safe to re-run)
- `scripts/enable-claude-login-item.sh` — adds Claude Code to macOS Login Items (macOS, safe to re-run, asks first in the setup flow)
- `scripts/auto-update.sh` — pulls code updates from GitHub (macOS/Linux, safe to re-run, never overwrites local changes)
- `com.today-dashboard.plist.example` — LaunchAgent template for always-on background serving
- `com.today-dashboard-autoupdate.plist.example` — LaunchAgent template for automatic `git pull`s
- `.claude/skills/setup-dashboard/` — the one-command setup flow used above
