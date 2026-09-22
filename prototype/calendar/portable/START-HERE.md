# Welcome to Today

Requires macOS 14 or later. Works on Apple silicon and Intel Macs.

1. Unzip Today.zip and move the whole Today folder somewhere permanent (for example, your home folder). Keep its contents together and outside a shared/cloud-synced folder.
2. Open Today.app. If macOS blocks this unnotarized app, and you trust the sender, use System Settings → Privacy & Security → Open Anyway after the first attempt. Managed Macs may not permit this; ask your IT team if blocked. Do not disable Gatekeeper.
3. Complete the connection checklist. Your calendars and Mail accounts must already be set up in Apple Calendar and Apple Mail.
4. Drag Today.app to the application side of the Dock. Keep the original folder; the Dock icon is only a shortcut.

If Today asks you to locate its project, choose this whole folder. This can happen because macOS relocates downloaded apps when launching them.

## Make it yours

Open this entire folder as a local project in Codex or Claude Code (or a Claude mode with permission to edit local files). Ordinary chat alone cannot edit these files.

Try: “Help me personalize Today. Ask about my weekly schedule and links, then update this project.”

Or: “Make my calendar wider and hide the verse.”

- custom/user.css and custom/user.js: your personal styles, layout overrides, and shortcuts; preserved during updates.
- dashboard/: standard app files. Direct edits here require a manual merge before an update can install.
- data/schedule.js: your personal weekly rhythm; starts blank.
- data/plan.js: your personal goals/onboarding plan; starts blank.
- examples/: generic examples for the AI to adapt, not your real data.

Restart Today after changing dashboard files. Schedule and plan edits appear when Today refreshes. No rebuild is needed for these customizations, and neither AI app needs to stay open for Today to work. Settings includes an Open customization folder button.

Calendar/Mail contents are read into memory, not exported into this project. Name, calendar/mailbox selection, permissions, and setup completion belong to your macOS user account. Copying this pristine folder to another Mac does not copy those settings. Weather and the daily verse require internet; the dashboard also uses optional online fonts and shortcut icons.

Keep a backup of your customized folder before applying updates. Do not send a personalized folder to another coworker; use the original blank archive.

Read UPDATES.md for built-in updates and the one-time installer for older Today folders. Settings → Updates accepts the publisher's shared link to latest.json.

This is a locally signed build, without an Apple Developer account or Apple notarization. First-launch approval and managed-device restrictions remain controlled by macOS.


## iPad companion (Today 0.3)

In Today on your Mac, open **Settings → iPad sharing → Start sharing**. Keep both devices on the same trusted Wi-Fi network. Scan the QR code using the iPad Camera and tap **Connect this iPad**. In Safari, choose **Share → Add to Home Screen → Open as Web App**.

- Sharing is off by default and does not restart automatically when Today reopens.
- The Mac must stay awake with Today open. The iPad polls the latest Mac snapshot every 15 seconds; the Mac’s existing Calendar/Mail refresh timing still applies. Refresh on the iPad fetches the latest available snapshot, not a new Mail sync.
- Calendar, Mail summaries, Asana tasks, weekly rhythm, weather, and plans come from your Mac. The focus timer runs independently on the iPad, catches up after sleep, and does not send background alarm notifications.
- Respond to invitations and open individual email messages on your Mac. The companion cannot remotely operate Mac apps. Web shortcuts open on the iPad. Native custom scripts are not loaded by the companion.
- This is a local HTTP connection, **not encrypted**. Use only a trusted private network; do not forward port 8787 to the internet. Anyone with the pairing link has read access while sharing runs.
- **Stop Sharing** invalidates all pairing links and sessions. Restarting sharing produces a new link. Data already displayed on an iPad may remain visible as an offline snapshot until closed or a revocation response is received.
- If a connection fails, check macOS Local Network permission and firewall access for Today. Office/guest Wi-Fi may block communication between devices. If the Mac’s network address changes, restart sharing and pair again; an existing Home Screen shortcut may need replacing.

The companion serves only explicitly listed UI files and an authenticated runtime snapshot; it does not expose the project folder or provide a remote-command endpoint. It is a first local companion version, not an independent iPad app or an internet-hosted service.

To load updated iPad UI during an active connection, tap **Update dashboard** at the top of the iPad page. If Today has restarted on the Mac, start sharing again and scan the new QR code first. Reloading keeps the timer and display preferences saved on that iPad.
