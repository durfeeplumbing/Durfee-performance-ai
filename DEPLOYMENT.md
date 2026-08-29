# Durfee Performance AI — Deployment

## Required infrastructure
1. Node.js hosting capable of running Next.js 15.
2. PostgreSQL database.
3. HTTPS on the employee portal domain.
4. A production identity/session provider with server-side role verification.

## Environment variables
Copy `.env.example` into the hosting provider's encrypted environment settings. Do not commit production values to GitHub.

Required initially:
- `DATABASE_URL`
- `DATABASE_SSL`
- `AUTH_SECRET`
- `NEXT_PUBLIC_APP_URL`

## Database
Run `db/schema.sql` against an empty PostgreSQL database before enabling database-backed screens. Backups, encryption, least-privilege database credentials and migration/version controls should be enabled before production use.

## Authentication
`lib/session.ts` is intentionally fail-closed until an identity provider is connected. The browser must never be allowed to choose its own role. The authenticated identity must be matched to the `users` table and authorization enforced server-side.

## Production readiness gate
Do not expose customer, employee, payroll, accounting or payment information until authentication, database security, backups, audit logging and HTTPS are verified. Payment card data should be handled by a compliant payment provider rather than stored in this application.

## Deferred integration
ServiceTitan integration remains intentionally out of scope for the current build.
