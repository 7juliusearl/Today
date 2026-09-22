# Local calendar prototype

A separate macOS 14+ app that reads Apple Calendar through EventKit and displays
selected calendars using the existing Today dashboard. No AI app, Google API key,
Slack connection, local web server, or cloud hosting is needed.

## Build and try it

On a development Mac with Xcode / Swift and Python 3 installed:

```sh
./scripts/build-calendar-prototype.sh
open "build/Today.app"
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

Refreshes update the existing page in place and preserve its scroll position and
expanded event details. The app refreshes every five minutes while running, when brought to the
foreground, and when Apple Calendar reports changes. After the Mac wakes, it
refreshes immediately and again after 15 seconds to allow syncing to resume.
It opens directly to your saved dashboard when Calendar access is already granted.
It does not fetch data while quit or while the Mac is asleep.

Use the **Always on top** pin toggle beside Settings in the dashboard toolbar to
keep Today above ordinary windows on every macOS desktop as you switch Spaces. Toggle it off to restore
normal window behavior. This preference defaults to off and is remembered after
restarting the app. This applies to regular desktops; full-screen apps keep their own Spaces.

Today remembers its window size and position using macOS window-frame saving.
The 1200 × 850 starting size is only a default for a new window. You can resize
down to 480 × 360 for narrow or short layouts; dashboard refreshes and pin changes
do not restore or reset the saved frame.

The toolbar's **Reserve dashboard space** menu offers an optional way to keep
enlarged windows from covering Today. Enable the option, then choose **Allow
window control…** and grant Today access in macOS Settings. Enabling the option
also turns on Always on top; turning off the pin pauses window adjustments.
Place Today along any screen edge. When the frontmost app's standard window fills
that same screen's usable area, Today fits it into the largest remaining rectangle,
leaving an 8-point gap. Wide dashboard layouts can leave room below; tall layouts
can leave room beside them. The option defaults to off and is remembered.

This is an adjustment after enlargement, not a system-wide reserved work area.
It waits for a stable window frame and mouse release, so a brief enlargement may
be visible. Manually sized windows, other monitors, dialogs, and true full-screen
windows are left alone. Title-bar double-click must enlarge the window to fill
the usable screen; an app-specific Zoom that only partially expands it is not
adjusted. Apps may impose minimum sizes or refuse Accessibility resizing.
Disabling the option stops further adjustments without changing current layouts.

If Today's macOS permission switch turns itself off, quit Today, remove its stale
entry from Accessibility (called Device Control and Data Access on some systems),
and add the current `build/Today.app` using the plus button. Enable it and reopen
Today. The toolbar shows a warning when window-control permission is missing and
can reveal the exact running app in Finder. Managed-device policy may also prevent
approval; a switch still reverting after re-adding needs administrator investigation.

The build refuses to overwrite a running Today process. By default builds are
ad-hoc signed, so their code identity changes with native updates and permissions
can need re-approval. Set `TODAY_SIGNING_IDENTITY` to an installed, stable code-signing
certificate for both build and packaging to retain a consistent signing identity.
This does not grant permissions automatically or repair an existing stale entry.

Window layout calculations can be checked without Accessibility permission:

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache \
  prototype/calendar/WindowSpace.swift prototype/calendar/WindowSpaceTests.swift \
  -o build/window-space-tests
build/window-space-tests
```

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

- Today, the next five dates with events within a 14-day lookahead, and up to 30
  pending invitations over the next 90 days when EventKit exposes the user's response status.
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

The Mail card shows all messages received today in the selected mailbox, including
read and unread messages, newest first. Today runs from midnight to the next
midnight in the Mac's local timezone. The card grows naturally with the page instead of clipping an inner scroll area.
Compact message rows show sender, time, subject, attachment count, and read status.
Unread messages have a subtle warm gradient outline and tint, a blue dot, an Unread label, and a bold sender; read messages
have a muted Read label and lighter sender weight. Status reflects Apple Mail at
the latest successful refresh. Clicking
anywhere on a row opens the message directly in Mail.
A subtle **Open Mail** link in the card header opens the full Apple Mail app even
before a mailbox is connected. It reads only sender,
subject, timestamp, attachment count, read status, and message identifiers. Headers remain in memory; only the
chosen mailbox/account identifiers and enabled setting are saved. Refreshing
never sends, deletes, or marks messages read. Clicking a header opens the message
in Mail, where normal Mail read/unread behavior applies.

Mail is checked on normal dashboard refreshes, with a one-minute cooldown to
avoid repeated calls during calendar update bursts. The Refresh button bypasses
that cooldown. A busy request is not duplicated. Failed reads retain the last
successful result with an error instead of claiming the data is current. Disconnecting clears
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

### Happening now

Below the greeting, the dashboard shows timed calendar events currently in
progress, with time remaining, an elapsed-time bar, and a Join meeting link when
available. Concurrent events appear together. All-day, declined, canceled, and
invalid-duration events are excluded. Start times are inclusive and end times
exclusive. Events starting within the next hour appear alongside active events with a
large right-aligned countdown: “Starting in” above the number and “minutes”
below it. It counts down in actual whole minutes (60, 59 … 2, 1), rounding partial
minutes up so zero never appears before the event starts. Once an
event begins, the same display shows “Time left” and remaining minutes. At the start time the event moves
to In progress. If only future events are highlighted, the heading reads
“Happening soon.” Beyond the one-hour window, the next event is shown as a
simple next-up line.
The existing 15-second clock tick updates the section without fetching data or
reloading the page.

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache \
  prototype/calendar/HappeningNowTests.swift -o build/happening-now-tests
build/happening-now-tests
```

### Responding to pending invitations

The pending list reads RSVP status from Apple Calendar over the next 90 days,
showing up to 30 invitations and grouping recurring events by calendar item ID.
The main upcoming-events list keeps its 14-day horizon. Past invitations are
excluded. **Respond in Calendar** uses Calendar's scripting interface to reveal
an event by its external identifier in the matching calendar. If it cannot find
an exact match, it opens the event date and directs you to Calendar's Invitations
inbox. macOS may request Automation permission for Calendar.

Apple's public EventKit and Calendar scripting interfaces expose attendee response
status as read-only. The dashboard does not send RSVPs. Use Calendar's Accept,
Maybe, or Decline controls; the dashboard updates after Calendar syncs the response.
This replaces the unreliable email-subject search; no Mail connection is needed
for invitations. Live event reveal depends on the identifiers exposed by the
calendar account and needs an interactive check.

### Version 2 compact overview

The `codex/main` branch bundles `overview.css` after the
shared dashboard styles. At window sizes of at least 1000 × 650 CSS pixels,
all dashboard sections fit within the window: greeting and current event at the
top; today's calendar, Mail, and upcoming days in the middle; work rhythm,
invitations, onboarding, and verse below; quick links along the bottom.
Long lists scroll inside their cards, with their position preserved on refresh.
Smaller windows retain the regular page layout for readability. Personal data
and native permissions use the same app settings as version 1.

### First-run setup

A branded native introduction stays visible until the user finishes setup and
chooses **Open my dashboard**. Calendar access and a valid calendar selection
are required. Location, Mail, and Calendar automation are explicit sequential
steps with completion indicators; optional steps can be deliberately skipped.
Weather refresh no longer requests location implicitly. Mail does not refresh
from the calendar model during setup; its connection step performs its own read
and only reports connected after a successful mailbox read. Calendar automation
uses a read-only calendar-list request, never an invitation response.
Denied permissions have Settings/retry options. Completion and skip choices
persist in user defaults. Existing installations see this introduction once.
Native macOS permission dialogs must still be tested interactively on a fresh
installation; rebuilding does not reset previously granted system permissions.

### Portable coworker folder

Run `./scripts/package-today.sh` to build an Apple silicon + Intel archive in a
new `build/Today-Share-*/` directory. Sharing uses an allowlist of UI assets,
blank personal files, generic examples, and AI customization instructions. It
never copies the developer's personal data directory, preferences, or repository.
The portable app uses its own bundle identity (`com.today-dashboard.portable`).
No paid Apple account is involved; the ad-hoc signature is not notarization, so
Gatekeeper or managed-device policies may still require approval or block launch.

Keep the whole Today folder together. The portable app finds `dashboard/` and
`data/` beside itself. If macOS translocates the downloaded app, a folder picker
locates the original project. Settings can reveal the folder for editing in Codex
or Claude Code. UI edits require an app restart; personal data scripts load on
refresh. Native changes still require rebuilding from this source repository.
Existing development builds keep their original personal-data path and identity.

### Email conversations

Today's messages are grouped using Message-ID, References, and In-Reply-To
headers. Shared ancestors may be outside today's fetched messages. No sender or
subject heuristic is used; missing/unavailable headers leave messages separate.
Only reply-chain IDs are retained from the raw headers; message bodies are never
read. Each group opens its latest message directly and offers a separate control
to show earlier messages received today. A group is unread if any member is
unread. Mail's proprietary conversation/category UI may group differently.

### Asana calendar deadlines

Settings → Asana tasks lets each user select a subscribed Asana calendar,
independently of the meeting calendar selection. In Asana, use My Tasks → Sync
to Calendar, then Apple Calendar → File → New Calendar Subscription. Reload the
calendar list in Today and save the selected subscription. No API token is used.
Today’s calendar includes Asana tasks due today, with links to the Asana desktop
launcher when a valid task URL is present. There is no separate Asana card.
Selected Asana events are excluded from the meeting lists. Calendar subscriptions
are one-way and may update slowly; no live completion status, undated tasks, or
write-back is claimed. Each coworker connects their own subscription locally.

### Portable updates

TodayUpdater.swift adds Settings → Updates, signed feed checks at launch/every
six hours, and user-initiated installation. TodayUpdateHelper waits for the old
app to exit, builds a replacement beside the project, and retains the original
folder under Today Backups. UpdateSupport.swift verifies Ed25519 signatures,
ZIP checksums, portable identity, app signatures, release metadata, and dashboard
baselines. V1 uses its bundled dashboard as the baseline. Conflicts stop an update.

Personal data and custom/user.css + custom/user.js survive; the web view loads
custom files after the standard assets. Refresh dispatches today:updated for
idempotent custom behavior. See portable/UPDATES.md and scripts/RELEASING.md.
The private release key is ignored by Git and excluded from every package.

Validation:

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache prototype/calendar/UpdateSupport.swift prototype/calendar/UpdateTests.swift -o build/update-tests
build/update-tests
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache prototype/calendar/UpdateSupport.swift prototype/calendar/UpdatePackageTests.swift -o build/update-package-tests
build/update-package-tests /path/to/new/Today.zip /path/to/old/Today
```

Package tests work on disposable copies and never launch a coworker's app or
change privacy settings. Apple launch/permission approval remains separate from
the release signature; updates do not remove quarantine or bypass Gatekeeper.
