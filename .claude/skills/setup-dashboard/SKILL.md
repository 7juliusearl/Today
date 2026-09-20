---
name: setup-dashboard
description: One-time interactive setup for the "Today" dashboard in this repo — connects the user's Google Calendar(s) and Slack, creates the scheduled data-refresh task, populates real data immediately, and gets the local server running. Use when the user opens this project and asks to set up, configure, or get their dashboard running.
---

You are setting up a fresh copy of the "Today" dashboard for a new person (not the original author). This is a static local site (`index.html` / `styles.css` / `app.js`) whose data comes from a scheduled Claude Code task that writes `data/dashboard.js`. Your job is to make this person's copy fully working with THEIR calendar, Slack, and machine — end to end, asking only what's necessary and doing the rest yourself.

**Tell the user this up front, before doing anything else** — it's the single most important thing to set expectations correctly: the data refresh (calendar, Slack, pending invites, sticky notes, verse) only happens while the **Claude Code desktop app is open**. The dashboard site itself, the local server, and weather all work fine with Claude Code closed — but nothing new gets fetched until it's open again (it catches up automatically on next launch, nothing is lost, it's just delayed). Because of this, Phase 1.5 below offers to make Claude Code launch automatically at login, which removes the problem for most people.

Work through these phases in order. Don't skip ahead — each one depends on the last.

## Phase 0 — Sanity check

Confirm you're in the right place: this directory should contain `index.html`, `app.js`, `styles.css`, and a `data/` folder with `*.example.js` files. If not, stop and tell the user this skill only works inside a clone of the Today dashboard repo.

Get the absolute path of this directory (`pwd`) — you'll need it later for the LaunchAgent.

## Phase 1 — Connect Google Calendar

Check installed connectors for "calendar". If Google Calendar isn't connected, use the connector-suggestion mechanism to prompt the user to connect it, and wait until they confirm before continuing — nothing else in this skill works without it.

Once connected, call `list_calendars` and show the user the list. Ask them (a simple multiple-choice or short question) which calendar is their **primary** one (usually their own email address) and whether there are any **additional shared/team calendars** they want merged in (e.g. a department or company events calendar). They can pick zero, one, or several additional calendars — don't assume.

Record: `PRIMARY_CALENDAR_ID` and `EXTRA_CALENDAR_IDS` (a list, possibly empty).

## Phase 1.5 — Offer to launch Claude Code at login (macOS only)

Explain briefly why this matters (see the note at the top) and ask if they want Claude Code to launch automatically at login so refreshes happen reliably without them thinking about it. This is a real system-settings change (macOS Login Items) — **ask first, don't just do it**.

- If yes: run `./scripts/enable-claude-login-item.sh`. It's safe and idempotent (checks whether Claude is already a login item before adding it), and tell them afterward it's reversible any time via System Settings → General → Login Items.
- If no or unsure: that's fine — just make sure they understand the tradeoff (stale data between launches) and move on. Don't push.

If they're not on macOS, skip this and just make sure they understand the tradeoff.

## Phase 2 — Connect Slack (optional)

Check installed connectors for "slack". If not connected, ask the user whether they want Slack activity on their dashboard at all — some people won't. If yes, suggest the connector and wait for them to connect it. If they decline or skip, that's fine — the dashboard already degrades gracefully with a "Slack isn't connected yet" message, and you'll tell the scheduled task to just report `connected: false`.

Record: `SLACK_ENABLED` (true/false). If enabled, mention to the user: a coworker can leave them an encouraging sticky note by DMing them on Slack starting with 📌 — it'll show up on the dashboard automatically after the next refresh.

## Phase 3 — Get their name

Ask (or infer from context you already have, e.g. their email) their first name for the greeting. Record `FIRST_NAME`.

## Phase 4 — Create the scheduled task

Ask what refresh cadence they want during the work day — a single early-morning run leaves the dashboard frozen the rest of the day, which defeats the point if they're planning to leave it open. Offer something like: hourly during work hours (light touch), every 30 minutes during work hours (fresher, roughly double the Calendar/Slack calls), or just once shortly before they typically arrive (lightest, but stale all day). Pick a matching cron — e.g. `0,30 8-17 * * 1-5` for every 30 min 8am–5pm weekdays, `0 8-17 * * 1-5` for hourly, or `0 8 * * 1-5` for once at 8am. All times are LOCAL, weekdays only unless they say otherwise.

Use `mcp__scheduled-tasks__create_scheduled_task` (taskId `refresh-dashboard-data`, cron from whatever they chose above) with a prompt you write yourself, following this reference shape. This exact design was arrived at through real trial and error — don't reinvent it, adapt it:

- **Today's events**: `list_events` for today's full range (00:00–23:59 local) on `PRIMARY_CALENDAR_ID` and each of `EXTRA_CALENDAR_IDS`. Map every non-declined event (see the RSVP note below) to a rich object: `id, title, start, end, allDay, location, calendar` ("personal" for the primary calendar, "team" for every extra one), `description` (plain text, HTML stripped, truncated ~600 chars), `meetingLink` (hangoutLink or a video-type conferenceData entryPoint), `organizer` ({name, email}, null if it's just the user), `attendees` (non-resource attendees, capped 15, each {name, email, responseStatus}), `attendeeCount`, `myResponseStatus` (the self attendee's responseStatus, or "organizer", or null), `status`, `recurring` (has a recurringEventId), `htmlLink`. Merge all calendars into one array sorted by start.
- **RSVP note (important)**: events awaiting the user's response (`responseStatus: "needsAction"` on their own attendee entry) are NOT declined — always include them. Only skip events where the user's own status is "declined".
- **The next few days**: same rich mapping, for tomorrow through 14 days out, grouped by calendar date, keeping the first 5 dates that have ≥1 event. Output as `calendar.upcoming`: an array of `{ date, events }`.
- **Pending invitations**: across everything fetched above, filter to `myResponseStatus === "needsAction"`, sort by start, cap at 10. Output as `calendar.pendingInvites`.
- **Slack** (only if `SLACK_ENABLED`): read the CURRENT `data/dashboard.js`'s `generatedAt` as a cutoff (fallback: 24h ago if missing/unreadable). There is NO unread/read-state API in the Slack tools available — don't look for one. First call `slack_list_user_channels` (types `public_channel,private_channel,mpim,im`, format `ids_only`, paging through if more results are available) to get the set of channels/DMs the person is an ACTUAL MEMBER of — call this `MEMBER_CHANNEL_IDS`. Then call the combined public+private search tool once with the cutoff as the top-level Unix-timestamp `after` param, `filters: "after:<cutoff date, one day earlier>"`, `content_types: "messages"`, `sort: "timestamp"`, `sort_dir: "desc"`, `limit: 20`, `include_bots: false`. Discard results at/before the exact cutoff, AND discard any message whose channel isn't in `MEMBER_CHANNEL_IDS` unless the message text contains a direct mention of them (`<@USER_SLACK_ID>` — see below). This second part matters: without it, messages from Slack Connect / external-org shared channels they can technically see but aren't really "in" will incorrectly show up as unread (this happened in testing — a message from an external partner org's shared channel appeared even though the person wasn't a member of it). Group what's left by channel/DM, build `{ channel, preview (~140 chars), unreadCount, permalink (the most recent message's permalink URL from the search result, or null) }` per group, cap at 8, sorted most-recent-first. Set `slack.connected: true` if the call succeeded (even with 0 results), `false` only if the call itself failed. If `SLACK_ENABLED` is false, always output `{ connected: false, items: [] }` without attempting any Slack call.

  To get `USER_SLACK_ID` for the mention check above: call `slack_read_user_profile` with no `user_id` argument (defaults to the current user) and read the `User ID` field from the result. Do this once during setup and bake the literal ID into the task prompt you write (it won't change).
- **Sticky note** (only if `SLACK_ENABLED`) — a coworker can leave an encouraging note that shows up as a physical-looking sticky note on the page. Real-world testing showed people trigger this inconsistently — some type an actual 📌 emoji, some type the literal shortcode `:pushpin:` which their Slack client doesn't always auto-convert, some just guess and type `note:`. Accept all three. Run THREE Slack searches with the same combined public+private search tool (merge results, dedupe by timestamp): `keywords: ["📌"]`, `keywords: ["pushpin"]`, and `keywords: ["note"]` — each with `filters: "is:dm"`, `content_types: "messages"`, `sort: "timestamp"`, `sort_dir: "desc"`, `limit: 10`, `include_bots: false`. From the merged results, keep only messages that (a) start with one of 📌 / `:pushpin:` / `note:` (case-insensitive) once trimmed — discard ones where it just appears mid-message, (b) weren't sent by the user themself, (c) are within the last 14 days. Take the single most recent survivor, strip whichever leading marker it used, and build `{ text, from (sender's display name), ts (ISO timestamp) }`. Output as `stickyNote`, or `null` if nothing survives or all three searches fail — never invent a placeholder. If `SLACK_ENABLED` is false, always output `stickyNote: null`.
- **Verse of the day**: WebFetch `https://beta.ourmanna.com/api/v1/get/?format=json&order=daily`, extract `verse.details.{text,reference,version}`. On failure, pick randomly from a small built-in fallback list (a few well-known verses) so the card is never empty.
- **Output**: overwrite `data/dashboard.js` (the exact path under this repo, using the absolute path from Phase 0) with:
  ```js
  // Auto-generated each morning by the "Refresh dashboard data" scheduled task.
  // Do not hand-edit — changes will be overwritten on the next refresh.
  window.DASHBOARD_DATA = {
    generatedAt: "<ISO timestamp with correct local offset>",
    userFirstName: "FIRST_NAME",
    calendar: { events: [...], upcoming: [...], pendingInvites: [...] },
    slack: { connected: <bool>, items: [...] },
    stickyNote: { text, from, ts } or null,
    verse: { text, reference, version }
  };
  ```
- Make the task silent (no chat report, just write the file) and defensive (any single step failing should degrade to an empty/safe default for that field, never leave the file unwritten).

After creating it, run it once immediately with `mcp__scheduled-tasks__run_scheduled_task` so they see real data right away instead of placeholder text. Tell them BEFORE you do this: this first run will likely prompt them to Allow each tool it touches for the first time (Calendar, Slack if enabled, the verse WebFetch) — ask them to keep an eye on Claude Code and click through those, it's not stuck. Those approvals get stored on the task itself and reused automatically on every future run, so this is a one-time thing, not something they'll be asked to do on an ongoing basis. Wait for it to succeed before moving on; if it fails, read the run's events to see why and fix the task rather than leaving it broken.

**Also create the on-demand checker** so the dashboard's Refresh button actually does something beyond reloading a stale file. This is what makes clicking Refresh get real data within ~2 minutes instead of waiting for the next scheduled slot:

Create a second task, taskId `refresh-dashboard-on-demand`, cron `*/2 8-17 * * 1-5` (adjust the hour range to match whatever work-day window you used for the main task), with this prompt:

> This is a silent, no-chat-report, cheap "checker" task. Do the minimum possible work.
>
> 1. Check whether the file `<absolute path>/data/.refresh-requested` exists (a simple file-existence check via Bash, e.g. `test -f` — do not use any other tools yet).
> 2. If it does NOT exist: stop immediately, no other tool calls. This is the common case and must stay cheap.
> 3. If it DOES exist: delete it immediately (so a rapid double-click doesn't double-trigger), then read `<absolute path to ~/.claude/scheduled-tasks/refresh-dashboard-data/SKILL.md>` and carry out EXACTLY the steps it describes, in full, writing to the exact same `data/dashboard.js`. Don't print a chat summary — just update the file and finish.

This new task will need its own first-time tool approvals too (a new task means new stored approvals, separate from the main task, even for tools like Bash that seem trivial) — run it once with the flag file already present (`touch data/.refresh-requested` yourself first) to trigger and clear that approval pass immediately, same as you did for the main task above.

## Phase 5 — Seed the optional personal files

`data/dashboard.js` now exists for real (previous phase). For the two *optional* extras, don't force them: briefly mention that `data/schedule.example.js` (weekly work rhythm) and `data/plan.example.js` (onboarding/goal plan) exist and can be copied to their non-`.example` names and hand-edited later if wanted — but don't do it for them unless they ask, since it's personal content only they should write.

## Phase 6 — Run it

From this directory, run `./start.sh` to open `http://localhost:4173` in their default browser (not Claude's own browser pane — it has no logins and calendar links won't resolve there). Confirm it actually loads with their real data.

Mention that the page auto-reloads itself every 10 minutes (already built in, nothing to set up) so an already-open tab picks up each scheduled refresh without anyone clicking the refresh button. The refresh button itself also does more than just reload — clicking it asks the on-demand checker task (set up in Phase 4) to do a real data pull within ~2 minutes, via a small `/api/refresh` endpoint on the custom local server (`scripts/server.py` — not plain `python -m http.server`, see Phase 7).

## Phase 7 — Keep it running, and keep it updated (macOS only)

Just do both of these automatically — don't ask first, they're fully reversible and low-risk:

**The server:**
1. Copy `com.today-dashboard.plist.example` to `~/Library/LaunchAgents/com.today-dashboard.plist`.
2. Replace the placeholder path inside it with this repo's real absolute path (from Phase 0).
3. `launchctl load -w ~/Library/LaunchAgents/com.today-dashboard.plist`.
4. Verify with `lsof -nP -iTCP:4173 -sTCP:LISTEN` and a `curl -sI http://localhost:4173/`.

**Auto-updates from the shared repo:** so future pushes (new features, fixes) reach this person without them thinking about it:
1. Copy `com.today-dashboard-autoupdate.plist.example` to `~/Library/LaunchAgents/com.today-dashboard-autoupdate.plist`.
2. Replace the placeholder path inside it (it points at `scripts/auto-update.sh` in this repo) with the real absolute path.
3. `launchctl load -w ~/Library/LaunchAgents/com.today-dashboard-autoupdate.plist`.
4. This pulls every 30 minutes via `git pull --ff-only` — safe by construction (never overwrites uncommitted local changes, never force-pushes, never touches their gitignored personal data files). Mention to them that if they've hand-edited a tracked file like `styles.css`, a conflicting incoming change will just be skipped (logged to `/tmp/today-dashboard-autoupdate.log`) rather than clobbering their edit — they'd resolve that with a manual `git pull` when they notice.

If they're not on macOS, skip both and just tell them to run `./start.sh` and `git pull` manually whenever they want to check for updates.

## Phase 8 — Dock icon (macOS only)

Also automatic, no browser menus needed: run `./scripts/install-dock-app.sh`. It builds a real `.app` bundle at `~/Applications/Today.app` with the custom "T." icon and pins it to the Dock.

This script is deliberately conservative — read the comments at the top of it before running: it only ever *adds* (never deletes or rewrites anything), and if a `Today.app` already exists there (e.g. they'd previously used Safari's "Add to Dock" themselves) it leaves it completely alone rather than touching it. Because of that, it's safe to just run.

**Do not** try to "clean up" or remove Dock entries yourself by editing `~/Library/Preferences/com.apple.dock.plist` directly (via `PlistBuddy -c "Delete ..."` or similar) — editing that file while the Dock process is running races with Dock's own writes and can silently delete the wrong array entry (this happened once while building this feature and removed two unrelated Dock icons that had to be manually restored). If something ever needs to be removed from the Dock, ask the user to drag it off themselves, or use only additive, idempotent operations (`defaults write ... -array-add`, gated by a `defaults read | grep` check) — never index-based deletes against a live plist.

If they're not on macOS, skip this and just mention the manual Add to Dock steps (Safari: File → Add to Dock; Chrome: install icon in the address bar) as an alternative.

## Wrap-up

Give a short summary of what's now live (which calendars, whether Slack is on, whether the LaunchAgent is running, whether the on-demand checker task is set up, whether Claude Code is now a login item, and whatever refresh cadence they chose in Phase 4) and remind them that only happens while Claude Code's desktop app is open; otherwise it catches up on next launch. If they skipped the login-item step, mention once more that they can run `./scripts/enable-claude-login-item.sh` any time later if stale data becomes annoying.
