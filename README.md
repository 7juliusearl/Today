# Today

A personal "command center" dashboard: today's calendar (including a shared team calendar), unread-ish Slack activity, a verse of the day, live weather, and your own weekly work rhythm / onboarding plan if you set them up. Runs entirely locally as a static site, refreshed every weekday morning by a Claude Code scheduled task.

Dark glass, rounded bento cards, a warm orange accent — designed to feel like a native macOS panel rather than a webpage.

## Features

- **Today's Schedule** — merges your personal Google Calendar with a shared team calendar, click any event to expand attendees, RSVP status, description, and meeting/calendar links
- **Coming Up** — the next day with something on it, when today's clear
- **Slack** — messages posted since the dashboard's last refresh (there's no true "unread" API, so this is the closest honest equivalent)
- **Verse of the Day** — pulled from a public verse API each morning
- **Weather** — live, via your browser's location, no API key needed
- **Work Schedule / Onboarding** *(optional)* — your own hand-maintained weekly rhythm and 30/60/90 plan, if you fill them in
- Light/dark toggle, a manual refresh button, and a custom Dock icon

## Setting this up for yourself

This dashboard is driven by [Claude Code](https://claude.com/claude-code) — a scheduled task does the data fetching (it needs access to your Google Calendar and, optionally, Slack), and everything else is a static site with no server-side code of its own.

**The short version:**

1. Install [Claude Code](https://claude.com/claude-code) if you don't already have it.
2. Clone this repo: `git clone https://github.com/7juliusearl/Today.git && cd Today`
3. Open this folder in Claude Code and say **"set up my dashboard"** (or run `/setup-dashboard`).

That's it — Claude walks you through connecting your calendar (and Slack, if you want it), creates your personal refresh schedule, pulls in real data immediately, and gets the local server running, using the [setup-dashboard skill](.claude/skills/setup-dashboard/SKILL.md) bundled in this repo. On macOS it also sets up the always-on background server and pins a real Dock icon automatically — nothing to click through in a browser menu.

<details>
<summary>Prefer to do it by hand instead?</summary>

1. **Connect your calendar (and optionally Slack)** to Claude Code — connectors settings.
2. **Copy `data/dashboard.example.js` to `data/dashboard.js`** so the page has something to show before your first refresh runs.
3. **Create a scheduled task** (`refresh-dashboard-data`, weekdays 6:30 AM) that regenerates `data/dashboard.js` — the [setup-dashboard skill](.claude/skills/setup-dashboard/SKILL.md) contains the exact task design (including some non-obvious lessons learned, like Slack having no real unread API). Point Claude at that file and have it build the same task manually.
4. **Run it once**, then `./start.sh` to open `http://localhost:4173` in your regular browser (not Claude's built-in one — no logins there).
5. **(Optional)** Copy `com.today-dashboard.plist.example` to `~/Library/LaunchAgents/com.today-dashboard.plist`, fix the path inside it, then `launchctl load -w ~/Library/LaunchAgents/com.today-dashboard.plist` to keep it running permanently.
6. **(Optional)** Dock icon: run `./scripts/install-dock-app.sh` (macOS, builds a real `.app` and pins it — safe to re-run), or do it manually via Safari → File → Add to Dock / Chrome's install-as-app.

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

## Files

- `index.html` / `styles.css` / `app.js` — the page
- `data/*.example.js` — the schema each optional data file expects; copy to the non-`.example` name and fill in
- `data/dashboard.js`, `data/schedule.js`, `data/plan.js` — your real, gitignored personal data
- `icons/` — app icon source (`source.svg`), generated PNGs, and `Today.icns` for the Dock app; `manifest.json` — PWA metadata
- `start.sh` — local server launcher
- `scripts/install-dock-app.sh` — builds and pins the Dock icon (macOS, safe to re-run)
- `com.today-dashboard.plist.example` — LaunchAgent template for always-on background serving
- `.claude/skills/setup-dashboard/` — the one-command setup flow used above
