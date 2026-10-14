# Employee access — September 21, 2026

Continues the existing standalone Durfee Performance AI app. ServiceTitan integration remains deferred.

## Changes

- Sign-in and the root URL open the employee's permitted workspace: owner/manager dashboard, technician field app, CSR workspace, marketing, or accounting.
- Personal permission overrides take precedence over role defaults. Revoked destinations fall back to an allowed area; accounts with no area have a restricted-access page with sign-out.
- The sidebar and landing route use the same permission resolution. Failed permission reads fail closed.
- Successful password sign-in requires an active, linked employee record. Unlinked/inactive accounts are signed out with a useful message.
- Employee invitation forms require matching passwords, reject malformed tokens, prevent duplicate submissions while pending, and distinguish confirmation-pending signup from an authenticated session.
- Added the PKCE email-confirmation callback at `/auth/callback`; it never follows a caller-provided destination. Invalid/expired confirmation links return to sign-in with an explanation.
- Permission redirects preserve refreshed session cookies. Restricted-page navigation no longer always sends staff to `/dashboard`.

## Verification

- TypeScript, production build, and lint passed. Eight existing lint warnings remain in unrelated files.
- Eight regression tests cover all six landing roles, revocations, overrides, unsupported roles, invitation-token shape, and public-route boundaries.
- `tests/employee-access.sql` passed 36 checks across all six roles against the existing database, including override precedence and inactive-account denial. All generated test data rolled back.
- Nine local production HTTP/action checks passed: login and setup messages, unavailable invite, restricted access, anonymous root redirect, callback failure/redirect confinement, and empty-login validation.

## Authenticated pilot and remaining checks

Owner sign-in was completed through the secure browser prompt. The preview opened the Command Center as Phillip Durfee with the owner role and the expected navigation. No employee password was changed or copied into source.

The authenticated check exposed a pre-existing timeout in the deferred ServiceTitan snapshot. The snapshot and estimate-funnel queries now remain disabled unless `SERVICETITAN_DASHBOARD_ENABLED=true`; standalone dashboard data remains available.

The full customer-to-payment UI pilot and other employee roles still need browser verification.

Email confirmation delivery is not tested. Where `NEXT_PUBLIC_APP_URL` is configured, its `/auth/callback` URL must be included in the Supabase Auth redirect allowlist. PKCE confirmation must be opened in the same browser that started signup. If no app URL is set, Supabase's configured redirect remains in use.

This increment does not connect banking, accounting feeds, phone/SMS providers, marketing accounts, or the custom portal domain.
