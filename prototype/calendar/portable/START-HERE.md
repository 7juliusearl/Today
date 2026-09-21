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

- dashboard/: editable HTML, JavaScript, colors, and layout.
- data/schedule.js: your personal weekly rhythm; starts blank.
- data/plan.js: your personal goals/onboarding plan; starts blank.
- examples/: generic examples for the AI to adapt, not your real data.

Restart Today after changing dashboard files. Schedule and plan edits appear when Today refreshes. No rebuild is needed for these customizations, and neither AI app needs to stay open for Today to work. Settings includes an Open customization folder button.

Calendar/Mail contents are read into memory, not exported into this project. Name, calendar/mailbox selection, permissions, and setup completion belong to your macOS user account. Copying this pristine folder to another Mac does not copy those settings. Weather and the daily verse require internet; the dashboard also uses optional online fonts and shortcut icons.

Keep a backup of your customized folder before applying updates. Do not send a personalized folder to another coworker; use the original blank archive.

This is a locally signed build, without an Apple Developer account or Apple notarization. First-launch approval and managed-device restrictions remain controlled by macOS.
