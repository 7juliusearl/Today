# Local calendar prototype

A separate macOS 14+ app that reads Apple Calendar through EventKit and displays
selected calendars using the existing Today dashboard. No AI app, Google API key,
Slack connection, local web server, or cloud hosting is needed.

## Build and try it

On a development Mac with Xcode / Swift and Python 3 installed:

```sh
./scripts/build-calendar-prototype.sh
open "build/Today Calendar Prototype.app"
```

1. Confirm your work events appear in Apple Calendar first. Enable Google calendar
   syncing there if necessary, subject to your organization's device policy.
2. Click **Connect calendars**. macOS asks for **Full Access** to calendars; that
   is Apple's permission level required to read existing events. This app only
   reads events and never saves, edits, or deletes them.
3. In **Settings**, select the calendars to display, choose your primary calendar
   (used for the personal/team label), and optionally enter your first name.
4. Click **Save**. The dashboard fills the window; use the toolbar gear to change
   these settings later. Compare today's events, all-day events, shared
   calendars, upcoming dates, invitations, and meeting links against Apple Calendar.
5. Use the dashboard's Refresh button after changing an event in Google and
   allowing Apple Calendar to sync. Refresh reads the local store; it does not
   force a Google sync.

The app refreshes every five minutes while running and when brought to the
foreground. It opens directly to your saved dashboard when Calendar access is
already granted. It does not start at login or run when quit. Calendar selections and
name are saved in this app's own preferences; event data stays in memory. The
normal dashboard files and existing scheduled tasks are not changed.

## Scope and limitations

- Today, the next five dates with events within a 14-day lookahead, and up to ten
  pending invitations when EventKit exposes the user's response status.
- Declined and canceled events are omitted. Recurring instances and overlapping
  multi-day events are included in their applicable dates.
- Meeting links are detected in synced event URLs, locations, or notes. Google
  conference metadata and Google event-page links are not guaranteed to sync.
- Personal versus team is determined by the chosen primary calendar. Calendar
  identifiers can change if an account is removed and re-added; reselect it then.
- Weekly work rhythm (including the hero summary), onboarding plan, weather,
  daily verse, and quick links are restored from the main dashboard. Slack and
  Slack-sourced sticky notes remain hidden.
- `data/schedule.js` and `data/plan.js` are read from this checkout on each refresh.
  The build records only their directory in the app configuration; it does not
  bundle personal files. Moving the checkout requires rebuilding the app. Missing
  files show the dashboard's normal empty states. Changes to these files remain
  local and gitignored.
- Weather uses native Location permission and sends approximate coordinates to
  Open-Meteo. Denying permission leaves the rest of the dashboard working. Weather
  updates at most every 30 minutes. The daily verse comes from OurManna, with a
  clearly labeled offline verse when no live verse has loaded. Fonts and quick-link
  icons use the same public services as the main dashboard. These requests never
  include calendar or personal schedule data.
- Managed Macs may restrict Calendar access or app installation.
- The build is locally signed for development and compiled for the current Mac's
  architecture. Coworker distribution, signing/notarization, login startup, and
  automatic updates are future work.

## Checks

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache \
  prototype/calendar/CalendarData.swift prototype/calendar/CalendarDataTests.swift \
  -o build/calendar-data-tests
build/calendar-data-tests
```

The tests use unsaved synthetic events, not anyone's real calendar. They cover
midnight boundaries, overnight overlap, all-day dates, meeting extraction,
unsafe URLs, the upcoming-date limit, occurrence IDs, and JSON output. Live
permission, account syncing, attendee responses, and visual layout still require
an interactive check on a Mac.
