# Updating Today

## Already using an older Today?

Keep this downloaded release folder separate from your existing Today folder. Open **Update Existing Today.command** in the new folder and select your **existing** Today folder. Confirm Update and restart. This uses tools already included with macOS; no compiler or AI app is needed. macOS may ask you to approve opening downloaded software. Never disable its security protections.

The installer replaces Today.app and dashboard/ together, keeps your personal data and custom/ files, and saves the previous complete folder under **Today Backups** beside your original folder. Your Dock shortcut keeps the same app path. Your Mac's stored preferences are not reset; macOS may ask for permissions again after an app update.

If the installer reports customized dashboard files, no update is installed. Ask Codex or Claude to read this file and migrate your edits before retrying. Do not replace your whole personal folder with the blank release.

## Future updates

In Today Settings → Updates, paste the **view-only shared file link to latest.json** provided by the publisher and save it. A link to the whole Dropbox folder won't work. If the release already includes the link, no setup is needed.

Today checks when it opens and every six hours while running. An update icon appears in the toolbar when a verified newer build is available. Open Settings to see the release notes and choose **Install update and restart**. Updates never install without that click. You can turn automatic checking off and use Check for updates instead.

Offline or failed downloads leave your current version in place. The app verifies the publisher's release signature and ZIP checksum before installation. This is separate from Apple signing/notarization and does not bypass macOS approval.

## Customizing without losing changes

- **custom/user.css**: personal layout and color overrides; loaded after the standard styles.
- **custom/user.js**: personal shortcuts and behavior; loaded after the standard dashboard. Run an idempotent customization function once, and register it with `window.addEventListener('today:updated', yourFunction)` if it needs to run again after refreshes.
- **data/schedule.js** and **data/plan.js**: your personal schedule and goals.
- **dashboard/**: standard release files. Editing these directly blocks automatic installation, so your work cannot be silently overwritten.

For v1 customization migration, compare dashboard/ with Today.app/Contents/Resources/dashboard (the original files shipped with that installation). Back up first. Move intentional changes into custom/user.css and custom/user.js, and then restore dashboard/ from that bundled original. Do not change the bundled app or .today-release.json. Some structural changes need manual adaptation; do not discard them just to pass the updater check. The new release adds the custom file hooks when it installs.

## Restore a backup

Quit Today. Move the current Today folder aside. Move the desired backup from Today Backups to the original folder location, with its original name, then reopen Today.app. UPDATE-RESULT.txt in the updated folder identifies the backup. Backups contain your personal customization files: keep them private. The updater does not delete them automatically.
