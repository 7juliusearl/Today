# Publish a Today update

The release host is a view-only Dropbox shared **file** link to latest.json. Coworkers need no Dropbox login or Apple Developer account. The local publisher uses a renewable Dropbox authorization stored in macOS Keychain. Only clean portable releases go in the shared folder.

## One-time publishing setup

The Ed25519 private key is in `.today-release-signing/private-key` (ignored by Git). Back it up privately, outside this project. Never include it in Dropbox releases or a coworker's folder. The public verification key in `update-public-key.txt` is bundled into Today. Losing/replacing the private key requires manually distributing a new trusted app; do not rotate it casually.

Compile the publisher utility from this project:

```sh
xcrun swiftc -parse-as-library -module-cache-path build/swift-module-cache prototype/calendar/UpdateSupport.swift scripts/ReleaseTool.swift -o build/release-tool
```

`build/release-tool init` is only for the original key setup. It refuses to replace existing keys.

Create `latest.json` in your release folder, obtain its view-only shared file link, and put that URL in `release.json` as `feedURL`. Preserve this file and its sharing link across releases. The updater automatically converts Dropbox preview links to downloads. The link must be downloadable without a Dropbox sign-in or password. A shared folder URL is only for humans browsing releases.

## Developer ID signing and notarization

Install a Developer ID Application certificate with its private key on the publishing Mac. Save `.today-signing.json` (ignored by Git) with `identity` set to its certificate fingerprint and `notaryProfile` set to `today-notary`. This file contains configuration only; private keys stay in Keychain. `TODAY_SIGNING_IDENTITY` and `TODAY_NOTARY_PROFILE` can override these settings.

Create an app-specific password in your Apple Account, then run this in your own Terminal and answer its prompts locally:

```sh
xcrun notarytool store-credentials today-notary
```

Supply your developer Apple Account, its team ID, and the app-specific password. Never put the password in Git or chat. Credentials are validated and stored in Keychain.

The build signs the updater helper and app with hardened runtime and secure timestamps. The app retains its Apple Events entitlement for Mail automation. The packager requires notarization credentials before building, signs the final portable bundle, submits it to Apple, staples and validates the accepted ticket, checks Gatekeeper, then creates the release ZIP. It stops on errors; it never silently falls back to an ad hoc release. The existing Dropbox feed-signing key is separate and unchanged.

Local builds without configured signing still allow explicit development use. On the publishing Mac, use the saved identity consistently. Moving existing users from ad hoc signing may require one final Keychain/privacy approval. Signing does not suppress locked-Keychain or user-denied-access prompts.

## Automated shipping (recommended)

One-time Dropbox authorization:

```sh
python3 scripts/dropbox-publisher.py connect --app-key YOUR_APP_KEY
python3 scripts/dropbox-publisher.py status
```

Use a scoped Full Dropbox app with `account_info.read`, `files.metadata.read`, `files.content.read`, `files.content.write`, `sharing.read`, and `sharing.write`. Full Dropbox is needed to keep using the existing shared release folder and permanent feed. Authorize in your browser and enter the one-time code in the local terminal. Do not paste codes or tokens into chat. The refresh token is stored in macOS Keychain, never in Git or a coworker package. `disconnect` removes the local credential; revoke the app in Dropbox Connected apps to revoke server-side access too.

For each new shipment:

1. Finish checks, commit and push the intended app changes, and set a strictly higher build in `release.json` before committing. Never reuse a build number for different contents.
2. Write release notes to a text file and quit Today.
3. From this repository run:

```sh
python3 scripts/dropbox-publisher.py ship /absolute/path/release-notes.txt
```

This builds the universal clean coworker package, saves a versioned archive in `build/releases/`, uploads it to `/Julius Espiritu/Today Dashboard`, obtains a public link, downloads and compares the exact bytes anonymously, signs the manifest with the existing release key, and updates the existing feed file in place. It then verifies the permanent public feed. Git commits/pushes are separate from this command.

To resume a shipment or publish a package that was already built and tested:

```sh
python3 scripts/dropbox-publisher.py publish \
  build/releases/Today-0.3.0-build11/Today-0.3.0-build11.zip \
  build/releases/Today-0.3.0-build11/release-notes.txt
```

Retries reuse matching uploaded archives. A release that is already live is verified without being republished. Different bytes under the same build number, downgrades, private download links, and a feed link that points to the wrong destination are rejected. The feed is updated only after archive verification, using its prior revision so concurrent changes are not overwritten. The previous signed feed is saved beside the local archive. A failed public verification after upload does not automatically roll back: retry the same publish command to inspect/verify the result. Never delete and recreate `latest.json`.

The publisher does not replace app testing. Validate the prepared package with the existing updater/package checks and perform a disposable older-copy update for app/updater changes. No signing-key rotation or manual Dropbox upload is needed during ordinary shipping.

## Manual fallback

Upload the clean ZIP using a unique build-specific filename, then generate the manifest:

```sh
build/release-tool manifest '/absolute/path/Today.zip' 'https://www.dropbox.com/…' '/absolute/path/release-notes.txt'
```

Replace the contents of the existing Dropbox `latest.json` with the generated file. Never delete/recreate it, and verify both public links without signing in.

For the first release, obtain the feed link using a placeholder latest.json, embed it, build once, upload the ZIP, then replace the placeholder contents with the signed manifest. v1 users run Update Existing Today.command once. Thereafter the built-in updater handles releases.

The custom/ folder is never overwritten by the updater. Direct edits in dashboard/ are detected against the release baseline (or v1's bundled dashboard) and block installation until migrated. Full previous folders are kept beside the installation under Today Backups. The app and installer never change system privacy settings, remove quarantine, or bypass Gatekeeper.

## Current publishing checklist

Keep the public feed file at its existing shared Dropbox link. Upload each clean ZIP under a unique name including its build number, for example `Today-0.3.0-build8.zip`. A ZIP upload alone does not announce an update: the final publishing step is replacing the contents of the existing `latest.json` with the signed manifest for that exact ZIP.

The ordinary coworker flow is Settings → Updates → Check for updates, then review and install. Automatic checks run on launch and every six hours; installation still waits for the user. Coworkers never need to enter a Dropbox link. Older copies without the updater need the one-time `Update Existing Today.command` migration first.

Device sharing uses the current network IP. Normal app updates preserve paired-device credentials on the Mac. A changed IP requires a new device bookmark and may require scanning again. A reserved IP on each network makes bookmarks more reliable.

Never change or re-zip an archive after generating its manifest. Upload and verify the ZIP first, generate the signed manifest from that exact archive and its shared file link, then replace the existing feed file without deleting it. Keep previous archives available for rollback. After publishing, confirm an older portable copy sees the new version/build and can install it. The development app does not install updates.
