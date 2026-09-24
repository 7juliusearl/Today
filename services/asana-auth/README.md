# Today Asana sign-in service

Deploy this directory as a separate Netlify site. Set the base directory to `services/asana-auth`, publish directory `public`, functions directory `netlify/functions`, and leave the build command empty. The root dashboard, data, signing keys, and native app must never be the publish directory.

Set these environment variables in Netlify's UI (Functions scope where available):

- `ASANA_CLIENT_ID`: the public app client ID.
- `ASANA_CLIENT_SECRET`: the current app secret, entered directly into Netlify; never commit it.
- `ASANA_REDIRECT_URI`: `https://YOUR-SITE.netlify.app/.netlify/functions/asana-callback`.

In the Asana app, uncheck “This is a native or command-line app,” then add and save that exact HTTPS redirect. The hosted sign-in replaces the private developer trial's OOB flow. Enable `tasks:read` and `workspaces:read` scopes. Restrict app distribution to the intended workspace(s). An organization's app approval policy still applies.

Redeploy after changing environment variables. The native app must be configured with the public site URL and client ID. It creates a random state and PKCE verifier, validates the callback, and stores each user's refresh token in their own macOS Keychain. No app secret belongs in the native bundle. The callback has a fixed custom-scheme destination; it accepts no user-supplied redirect URL.

The service only exchanges authorization codes and renews credentials. It does not fetch or store task content. Do not enable request-body logging or add token values to logs. Token responses are non-cacheable; upstream failures are sanitized. Deploying the server is only one part of integration: native sign-in and end-to-end checks are required before coworker rollout.

Local service checks: `node --test tests.mjs`.
