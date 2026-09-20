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

The app refreshes every five minutes while running, when brought to the
foreground, and when Apple Calendar reports changes. After the Mac wakes, it
refreshes immediately and again after 15 seconds to allow syncing to resume.
It opens directly to your saved dashboard when Calendar access is already granted.
It does not fetch data while quit or while the Mac is asleep.

Enable **Launch at login** in Settings to have macOS open the app at sign-in.
This switch applies immediately, independently of Save/Cancel for calendar
selections. It defaults to the actual macOS login-item state (off until enabled).
If macOS requires approval, Settings provides a button to open Login Items.
Registration errors are displayed and the switch continues to reflect system
state. Keep the prototype app in its current location after enabling it; moving
or deleting the build may require registering it again. Calendar selections and
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
  architecture. Coworker distribution, signing/notarization, and automatic updates are future
  work. Launch at login uses this development app at its current path.

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

### Login and wake checks

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache \
  prototype/calendar/AppLifecycle.swift prototype/calendar/AppLifecycleTests.swift \
  -o build/app-lifecycle-tests
build/app-lifecycle-tests
```

These checks use a fake login service and isolated notification centers; they do
not register login items, change calendars, or put the Mac to sleep. They verify
registration/removal, approval and failure handling, external setting changes,
immediate and delayed wake refresh, coalescing calendar updates, and cleanup.

For live verification, enable Launch at login and confirm the app appears in
System Settings → General → Login Items. At the next normal sign-in, confirm it
opens with saved calendars. With the app running, sleep and wake the Mac and
compare with Apple Calendar after syncing finishes. Actual sign-in and sleep/wake
behavior require this interactive check; automated notification tests do not
prove OS launch approval or Google sync timing.

### Apple Mail

Open Settings → Apple Mail → **Connect / reload mailboxes**. Allow the macOS
Automation prompt, choose your work Inbox, and click **Use mailbox**. Connection
and disconnection apply immediately, independently of the calendar Save button.
Mail may launch in the background when queried; it must have your account set up.

The Mail card shows the selected mailbox's total unread count and up to eight
newest unread messages received within the past 14 days. It reads only sender,
subject, timestamp, and message identifiers. Headers remain in memory; only the
chosen mailbox/account identifiers and enabled setting are saved. Refreshing
never sends, deletes, or marks messages read. Clicking a header opens the message
in Mail, where normal Mail read/unread behavior applies.

Mail is checked on normal dashboard refreshes, with a one-minute cooldown to
avoid repeated calls during calendar update bursts. The Refresh button bypasses
that cooldown. A busy request is not duplicated. Failed reads retain the last
successful result with an error and a last-update label. Disconnecting clears
message data and ignores any in-flight result. No Gmail API key is needed.

Automation permission is broader than read-only. The bundled automation contains
only mailbox/header reads, runs outside the UI process, and has a 30-second
limit. If permission was denied, allow the app under System Settings → Privacy &
Security → Automation and reconnect. The selector lists account mailboxes exposed
by Mail; nested mailbox navigation is not yet provided.

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache \
  prototype/calendar/MailReaderTests.swift -o build/mail-reader-tests
build/mail-reader-tests
```

These tests use a fake Mail scripting interface and do not read real email.
Actual permission, mailbox enumeration, and opening messages require a live check.
