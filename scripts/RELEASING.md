# Publish a Today update

The release host is a view-only Dropbox shared **file** link to latest.json. No Dropbox tokens or Apple Developer account are used. Only clean portable releases go in the shared folder.

## One-time publishing setup

The Ed25519 private key is in `.today-release-signing/private-key` (ignored by Git). Back it up privately, outside this project. Never include it in Dropbox releases or a coworker's folder. The public verification key in `update-public-key.txt` is bundled into Today. Losing/replacing the private key requires manually distributing a new trusted app; do not rotate it casually.

Compile the publisher utility from this project:

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache prototype/calendar/UpdateSupport.swift scripts/ReleaseTool.swift -o build/release-tool
```

`build/release-tool init` is only for the original key setup. It refuses to replace existing keys.

Create `latest.json` in your release folder, obtain its view-only shared file link, and put that URL in `release.json` as `feedURL`. Preserve this file and its sharing link across releases. The updater automatically converts Dropbox preview links to downloads. The link must be downloadable without a Dropbox sign-in or password. A shared folder URL is only for humans browsing releases.

## Each release

1. Update `release.json` with a new display version and a strictly higher numeric build. Never reuse a build for a different archive.
2. Quit Today and run `./scripts/package-today.sh`. Use the printed clean Today.zip, never a user's customized folder.
3. Upload that ZIP with a versioned name (for example Today-0.2.0.zip) and obtain its view-only shared link.
4. Write the user-facing changes to a release-notes text file. Generate the signed manifest:

```sh
build/release-tool manifest '/absolute/path/Today.zip' 'https://www.dropbox.com/…' '/absolute/path/release-notes.txt'
```

5. The tool writes latest.json beside the ZIP. Update the contents of the **existing** latest.json in Dropbox after the ZIP is fully uploaded; don't delete/recreate the shared file. Do not edit the generated manifest: its exact payload is signed.
6. In an older disposable portable copy, Check for updates, review notes, then install and verify. Confirm the file links work without being signed into Dropbox. If Dropbox changes or revokes the feed link, distribute the replacement through Settings or a manual release.

For the first release, obtain the feed link using a placeholder latest.json, embed it, build once, upload the ZIP, then replace the placeholder contents with the signed manifest. v1 users run Update Existing Today.command once. Thereafter the built-in updater handles releases.

The custom/ folder is never overwritten by the updater. Direct edits in dashboard/ are detected against the release baseline (or v1's bundled dashboard) and block installation until migrated. Full previous folders are kept beside the installation under Today Backups. The app and installer never change system privacy settings, remove quarantine, or bypass Gatekeeper.

## Current publishing checklist

Keep the public feed file at its existing shared Dropbox link. Upload each clean ZIP under a unique name including its build number, for example `Today-0.3.0-build8.zip`. A ZIP upload alone does not announce an update: the final publishing step is replacing the contents of the existing `latest.json` with the signed manifest for that exact ZIP.

The ordinary coworker flow is Settings → Updates → Check for updates, then review and install. Automatic checks run on launch and every six hours; installation still waits for the user. Coworkers never need to enter a Dropbox link. Older copies without the updater need the one-time `Update Existing Today.command` migration first.

Device sharing uses the current network IP. Normal app updates preserve paired-device credentials on the Mac. A changed IP requires a new device bookmark and may require scanning again. A reserved IP on each network makes bookmarks more reliable.

Never change or re-zip an archive after generating its manifest. Upload and verify the ZIP first, generate the signed manifest from that exact archive and its shared file link, then replace the existing feed file without deleting it. Keep previous archives available for rollback. After publishing, confirm an older portable copy sees the new version/build and can install it. The development app does not install updates.
