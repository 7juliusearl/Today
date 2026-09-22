# Customize Today

This is a portable macOS dashboard project, not a website needing a server.
Read START-HERE.md. Ask about the user's preferences when they aren't specified.

Read UPDATES.md. Put personal styling in custom/user.css and behavior/shortcut changes in custom/user.js. They load after the standard dashboard and survive updates. Run an idempotent customization function once, then attach it to window's today:updated event if it must run after a refresh. Preserve element IDs and native bridge actions. Do not edit dashboard/ or .today-release.json for ordinary customization: the updater checks these standard files and blocks if modified. Structural changes that cannot use custom/ require a deliberate manual merge on future updates.

For older v1 folders, compare dashboard/ to Today.app/Contents/Resources/dashboard and back up before migrating differences to custom/. Restore the original dashboard files only after every intended change has been preserved. Never alter the bundled app or baseline to suppress a conflict.

Edit data/schedule.js and data/plan.js for the user's personal content. Both intentionally start as null. Use the matching files in examples/ to understand the schema; do not activate example people, dates, or schedules as the user's own. Set a real requested startDate for a plan.

The native app injects current calendar, Mail, and weather data at runtime. Never replace it with fabricated/live data files or ask for API keys. Do not fetch or export email/calendar contents to customize presentation. Native runtime data is not part of this folder.

Keep any personal customization within this project. Do not edit Today.app: it is a compiled signed bundle. No compiler is needed for HTML/CSS/JS or schedule/plan changes. Native features/permissions require a source rebuild and macOS developer tools; explain that boundary if requested. Do not disable Gatekeeper, remove quarantine, change macOS permissions, or automate Allow buttons.

When adding links use the user's chosen URLs. Escape dynamic text rendered as HTML. Keep existing message-opening, invitation-opening, refresh, and theme actions working. Retain readable small-window behavior. Data scripts set window.WORK_SCHEDULE and window.ONBOARDING_PLAN; they do not call external services.

Validate JavaScript syntax and review edited selectors/IDs. Restart Today after layout edits. Personal schedule/plan edits can use Refresh. Back up files before extensive edits. Do not upload the folder or publish changes without the user's request.
