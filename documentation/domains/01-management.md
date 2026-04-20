# Accounts and Access

**Implemented Domain:** `GnomeGarden.Accounts`
**Purpose:** Authentication, user identity, and session-token lifecycle

This file keeps the old `01-management` slot, but the implemented boundary is `Accounts`, not a broader management/settings domain.

## Resources

### `User`
The authenticated operator identity used across the app.

### `Token`
Authentication and session token records used by the auth layer.

## Current Scope

Implemented today:
- user accounts
- magic-link authentication
- session and token management
- actor context for Ash actions and LiveViews

Not implemented as a standalone management domain:
- company-wide settings resource
- role catalog resource
- org-wide admin configuration model

## UI Surface

Primary auth routes:
- `/sign-in`
- `/register`
- `/auth/*`

These routes are still driven by AshAuthentication/Phoenix overrides. They are separate from the main cockpit-style operator UI.

## Notes

- The main operator UI assumes a current user actor, but authorization policy is still a future tightening step.
- Durable business ownership belongs in the business domains, not in `Accounts`.
