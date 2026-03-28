# Management Domain

**CSIA Area:** General Management
**Module:** `GnomeHub.Management`
**Purpose:** Identity, authentication, company settings

---

## Overview

The Management domain handles user identity, authentication, and company-wide settings. It uses passwordless magic link authentication and provides the foundation for all other domains.

---

## Resources

### User
Authenticated user accounts.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| email | ci_string | yes | Unique email (case-insensitive) |
| role | atom | yes | Permission level |
| inserted_at | utc_datetime | auto | Created timestamp |
| updated_at | utc_datetime | auto | Modified timestamp |

**Role Values:**
- `:admin` - Full system access
- `:user` - Standard user access
- `:viewer` - Read-only access

**Actions:**
- `read` - List/get users
- `create` - Register new user
- `request_magic_link` - Send login email
- `sign_in_with_magic_link` - Complete authentication

### Role
Permission level definitions (embedded).

| Value | Access Level |
|-------|--------------|
| `:admin` | Full CRUD on all resources |
| `:user` | CRUD on owned resources |
| `:viewer` | Read-only access |

### Setting
Company-wide configuration.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| key | string | yes | Setting key |
| value | string | yes | Setting value |
| category | atom | yes | Setting category |

**Categories:**
- `:company` - Company info (name, address)
- `:billing` - Default billing terms
- `:notifications` - Alert preferences
- `:integrations` - API keys, webhooks

---

## Authentication Flow

```
┌────────────────┐
│  Enter Email   │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│ Request Magic  │
│     Link       │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│  Email Sent    │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│  Click Link    │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│ Session Created│
└────────────────┘
```

---

## Relationships

| From | To | Type |
|------|-----|------|
| User | HR.Member | has_one |
| User | All domains | owner |

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/sign-in` | Magic link request |
| `/auth` | Token validation |
| `/settings` | Company settings |
| `/users` | User management (admin) |

---

## File Structure

```
lib/gnome_hub/
├── management.ex
└── management/
    ├── user.ex
    └── setting.ex
```
