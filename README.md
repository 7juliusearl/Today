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

1. **Clone this repo** somewhere on your machine, e.g. `~/Projects/Today`.

2. **Connect your calendar (and optionally Slack)** to Claude Code, if you haven't already — Claude Code → connectors.

3. **Copy the example data files** so the dashboard has something to show immediately:
   ```bash
   cp data/dashboard.example.js data/dashboard.js
   cp data/schedule.example.js data/schedule.js   # optional
   cp data/plan.example.js data/plan.js           # optional
   ```
   These three are gitignored — they hold your personal calendar/Slack/schedule data and are never meant to be committed.

4. **Create a scheduled task in Claude Code** that regenerates `data/dashboard.js` every weekday morning. Ask Claude something like:

   > Set up a scheduled task that runs weekdays at 6:30 AM, pulls today's events from my Google Calendar(s) and recent Slack activity, fetches a verse of the day, and writes the result to `data/dashboard.js` in this project — matching the shape in `data/dashboard.example.js`.

   Claude can read this repo's `app.js` to see exactly what fields each section expects. Run it once manually the first time to confirm it works and to grant any tool permissions.

5. **Run the server and open it:**
   ```bash
   ./start.sh
   ```
   This opens `http://localhost:4173` in your default browser (not Claude's built-in browser — that one has no logins of its own, so calendar links won't resolve there).

6. **(Optional) Keep it running permanently.** Copy `com.today-dashboard.plist.example` to `~/Library/LaunchAgents/com.today-dashboard.plist`, replace the placeholder path with this repo's absolute path, then:
   ```bash
   launchctl load -w ~/Library/LaunchAgents/com.today-dashboard.plist
   ```
   Now the server starts automatically at login and restarts itself if it ever crashes.

7. **(Optional) Turn it into a Dock app** for the full command-center feel:
   - **Safari**: open the page, then File → Add to Dock
   - **Chrome**: open the page, click the install icon in the address bar (or ⋮ → Cast, save, and share → Install page as app)

   The favicon/manifest are already set up so it picks up the custom "T." icon and the name "Today" automatically.

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
- `icons/` — app icon source and generated sizes, `manifest.json` — PWA metadata for Dock/install
- `start.sh` — local server launcher
- `com.today-dashboard.plist.example` — LaunchAgent template for always-on background serving
