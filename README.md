# Durfee Performance AI

AI-powered operating system for Durfee Plumbing & Heating: profitability, dispatch, technician/CSR performance, pricing intelligence, marketing, and management reporting.

## Phase 1
- Owner command center
- CSR/dispatcher dashboard
- Technician scorecards and coaching
- Job profitability and gross-profit guardrails
- Smart dispatch recommendations
- AI price-book engine with actual-time feedback
- ServiceTitan integration layer
- Role-based access controls
- Daily profitability and billing exception reports

## Planned integrations
ServiceTitan, supplier pricing feeds, phone/SMS, accounting/banking, payroll, marketing/ad platforms, reviews, and GPS/field data.

## Architecture
Next.js + TypeScript application, PostgreSQL-compatible data layer, server-side integration adapters, role-based authorization, and immutable audit logging for sensitive operational and financial changes.

AI recommendations are advisory by default. Pricing, payroll, accounting, permission, and other consequential changes require authorized human approval.
