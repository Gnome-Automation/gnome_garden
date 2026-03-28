# Workspace Domain

**CSIA Area:** — (GnomeHub Unique)
**Module:** `GnomeHub.Workspace`
**Purpose:** Personal productivity, quick capture, inbox management

---

## Overview

The Workspace domain provides personal productivity tools. Quick capture from voice or text, an inbox for items needing attention, and reminders. Captured items are routed by AI to the appropriate domain.

---

## Resources

### Capture
Raw input from voice or text, pending AI processing.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| content | string | yes | Raw captured text |
| source | atom | yes | Input source |
| processed | boolean | yes | AI processed flag |
| intent | atom | no | Detected intent |
| routed_to | string | no | Destination resource type |
| routed_id | uuid | no | Destination resource ID |
| user_id | uuid | yes | Capturing user |

**Source Values:**
- `:voice` - Voice transcription (Twilio, web)
- `:text` - Direct text input
- `:email` - Email forward
- `:sms` - Text message

**Intent Values (detected by AI):**
- `:task` - Action item → Projects.Task
- `:note` - Information → Sales.Note
- `:reminder` - Time-based → Workspace.Reminder
- `:contact` - Person info → Sales.Contact
- `:ticket` - Support issue → Service.Ticket
- `:unknown` - Needs triage → Workspace.Inbox

**Actions:**
- `create` - Capture new input
- `process` - AI intent detection
- `route` - Send to destination domain

### Inbox
Queue for items requiring manual attention.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| title | string | yes | Item summary |
| content | string | no | Full content |
| source_type | string | no | Origin type |
| source_id | uuid | no | Origin ID |
| priority | atom | yes | Urgency level |
| status | atom | yes | Processing status |
| user_id | uuid | yes | Owner |

**Priority Values:**
- `:high` - Urgent attention
- `:normal` - Standard priority
- `:low` - When convenient

**Status Values:**
- `:unread` - Not yet viewed
- `:read` - Viewed but not actioned
- `:actioned` - Processed
- `:archived` - Completed

**Actions:**
- `mark_read` - Update status
- `action` - Process item
- `archive` - Complete item

### Reminder
Time-based notifications.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| title | string | yes | Reminder subject |
| body | string | no | Details |
| remind_at | utc_datetime | yes | Trigger time |
| recurrence | atom | no | Repeat pattern |
| status | atom | yes | Current state |
| related_type | string | no | Related resource type |
| related_id | uuid | no | Related resource ID |
| user_id | uuid | yes | Owner |

**Recurrence Values:**
- `:once` - Single occurrence
- `:daily` - Every day
- `:weekly` - Every week
- `:monthly` - Every month

**Status Values:**
- `:pending` - Waiting to fire
- `:triggered` - Notification sent
- `:snoozed` - Delayed
- `:dismissed` - Cancelled

**Actions:**
- `trigger` - Fire notification
- `snooze` - Delay by interval
- `dismiss` - Cancel

---

## Voice Capture Flow

```
┌─────────────────┐
│   Voice Input   │
│ (phone/web mic) │
└────────┬────────┘
         │
         │ transcribe (Twilio/Whisper)
         ▼
┌─────────────────┐
│    Capture      │
│   (created)     │
└────────┬────────┘
         │
         │ AI processes
         ▼
┌─────────────────┐
│   LLM Parser    │
│ (intent detect) │
└────────┬────────┘
         │
    ┌────┼────┬──────────┬──────────┬──────────┐
    ▼    ▼    ▼          ▼          ▼          ▼
┌──────┐┌──────┐┌──────────┐┌──────────┐┌──────────┐
│ Task ││ Note ││ Reminder ││  Ticket  ││  Inbox   │
│(Proj)││(Sale)││ (Wkspc)  ││ (Serv)   ││ (Wkspc)  │
└──────┘└──────┘└──────────┘└──────────┘└──────────┘
```

## Intent Detection Patterns

The AI parser looks for patterns:

| Pattern | Intent | Destination |
|---------|--------|-------------|
| "Call/email/meet with..." | task | Projects.Task |
| "Remember that..." | note | Sales.Note |
| "Remind me to..." | reminder | Workspace.Reminder |
| "Add contact..." | contact | Sales.Contact |
| "Customer reported..." | ticket | Service.Ticket |
| Unclear | unknown | Workspace.Inbox |

**Example Captures:**
```
"Call John at Acme about the panel upgrade"
→ Task: "Call John at Acme - panel upgrade"
→ Linked to: Sales.Company (Acme), Sales.Contact (John)

"Remember that ABC Corp prefers Tridium over Rockwell"
→ Note: "ABC Corp prefers Tridium over Rockwell"
→ Linked to: Sales.Company (ABC Corp)

"Remind me to follow up with the water district Friday"
→ Reminder: "Follow up with water district"
→ remind_at: Friday 9am

"The HMI at XYZ plant is showing comm errors"
→ Ticket: "HMI comm errors at XYZ plant"
→ Linked to: Engineering.Asset, Service.Ticket
```

---

## Inbox Workflow

```
Items arrive in Inbox
         ↓
    User reviews
         ↓
   ┌─────┴─────┐
   ↓           ↓
 Route      Archive
 manually    (if junk)
   ↓
 Create appropriate record
 (Task, Note, Ticket, etc.)
```

---

## Reminder Notifications

```
Reminder (pending)
         ↓
    remind_at reached
         ↓
┌─────────────────┐
│  Send Push/Email │
│  (via Oban job) │
└────────┬────────┘
         │
    User sees notification
         │
    ┌────┴────┐
    ↓         ↓
 Snooze    Dismiss
 (+15min)
```

---

## Integration with Other Domains

| Domain | Integration |
|--------|-------------|
| Projects | Captures → Tasks |
| Sales | Captures → Notes, Contacts |
| Service | Captures → Tickets |
| Management | Reminders owned by User |

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/capture` | Quick capture (voice/text) |
| `/inbox` | Inbox queue |
| `/reminders` | Reminder list |

---

## Mobile Experience

Workspace is optimized for mobile:
- Voice button always accessible
- Inbox as home screen widget
- Push notifications for reminders
- Quick capture from lock screen (future)

---

## File Structure

```
lib/gnome_hub/
├── workspace.ex
└── workspace/
    ├── capture.ex
    ├── inbox.ex
    └── reminder.ex
```
