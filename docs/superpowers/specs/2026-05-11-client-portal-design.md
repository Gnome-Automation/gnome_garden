# Client Portal Design

**Date:** 2026-05-11
**Status:** Approved
**Scope:** Client-facing portal — invoice viewing, agreement status, and online payment via Stripe + Mercury ACH

---

## Goal

Give clients a dedicated, authenticated portal to view their invoices and active agreements, pay online by card (Stripe) or wire/ACH (Mercury), and track their billing history — without needing to contact staff for status updates. Built to scale to many clients with multiple invoices each.

---

## No Separate Staff Portal Needed

The existing internal app is the management layer for everything the client portal displays. Staff manage data through the internal app; clients see the results in the portal.

| Action | Where it happens |
|---|---|
| Create/issue invoices | Internal app `/finance/invoices` (already built) |
| Manage agreements | Internal app `/commercial/agreements` (already built) |
| Grant client portal access | "Invite to portal" button on Organization show page (new) |
| View invoice payment status | Internal app `/finance/invoices` (already built) |

The client portal is **read-only for clients** — they can view and pay, never create or edit. All data entry is done by staff in the internal app.

---

## Key Decisions

- **Separate `ClientUser` resource** — client auth is completely isolated from internal staff `User`. One new table (`client_users`), no role flags on the existing user table.
- **Magic link auth** — same mechanism as staff (AshAuthentication), but a separate strategy on the new `ClientUser` resource. No passwords to manage.
- **Both invite + self-serve access** — staff can invite clients from the Organization page; clients can also self-register by entering their email if it matches a known `Person` affiliated with an org.
- **Project-focused portal** — invoices + agreement status. Industry standard for B2B engineering/professional services (consistent with HoneyBook, Bonsai, Dubsado).
- **Stripe fully integrated** — payment link auto-generated when invoice is issued. 3% fee passed to client. `stripe_payment_url` stored on invoice.
- **Mercury ACH always shown** — primary payment method, displayed on every invoice detail page.
- **Multi-tenant isolation via Ash policies** — every portal query is scoped to `actor.organization_id` at the data layer. URL tampering returns 404, never leaks data.

---

## Architecture

```
/portal (public)
  └── /login              ClientUser magic link entry
  └── /sign-in            AshAuthentication magic link landing

/portal (authenticated — ClientUser session)
  └── /                   Dashboard: outstanding balance, recent invoices
  └── /invoices           Invoice list
  └── /invoices/:id       Invoice detail + pay (Stripe + Mercury ACH)
  └── /agreements         Agreement list
  └── /agreements/:id     Agreement detail + linked invoices

Internal (staff only)
  └── Organization show   "Invite to portal" button → sends magic link to client
```

---

## Section 1: Auth & Access

### ClientUser Resource

New `GnomeGarden.Accounts.ClientUser` Ash resource in the `Accounts` domain.

```elixir
# lib/garden/accounts/client_user.ex
attributes:
  - id: uuid PK
  - email: :ci_string, allow_nil?: false
  - organization_id: uuid, FK → organizations, allow_nil?: false

identity: unique_email_per_org [:email, :organization_id]
  (NOTE: unique on (email, organization_id) not email alone — a person may be a
   contact for multiple client orgs. Each org gets its own ClientUser record.)

AshAuthentication:
  tokens do
    enabled? true
    token_resource GnomeGarden.Accounts.ClientUserToken  ← NEW separate token resource
    signing_secret GnomeGarden.Secrets                   ← reuse existing Secrets module
    store_all_tokens? true
    require_token_presence_for_authentication? true
  end

  strategies do
    magic_link do
      identity_field :email
      registration_enabled? true  (upsert on first magic link click)
      sender GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail
    end
  end
```

**`ClientUserToken` resource:** A new `GnomeGarden.Accounts.ClientUserToken` Ash resource is required by AshAuthentication to store and validate magic link tokens for `ClientUser`. It follows the same pattern as the existing `GnomeGarden.Accounts.Token` resource but is scoped to `ClientUser`. AshAuthentication will raise a configuration error at startup if this is missing. Add `use AshAuthentication.TokenResource` and register it in the `Accounts` domain alongside `Token`.

### Invite Flow (staff → client)

On the Organization show page, a new **"Invite to portal"** button opens a modal to select a person to invite. Fires `ClientUser.invite_to_portal(email, organization_id)` which upserts the `ClientUser` and sends a magic link via `ClientInviteEmail` (new Swoosh module).

### Self-Serve Flow (client)

Client navigates to `/portal/login`, enters their email. If the email matches a `Person` affiliated with an `Organization`, a magic link is sent. If no match: generic "if you have an account, check your email" message — no information leakage about whether the email exists.

The self-serve lookup:
```elixir
# Find org_id via Person.email → OrganizationAffiliation → Organization
# If found: upsert ClientUser(email, organization_id), send magic link
# If not found: silently succeed (same response either way)
```

### Session

Portal LiveViews use a dedicated `on_mount` hook (separate from staff `:live_user_optional`). `current_client_user` is always set and passed as `actor` to every Ash query. The hook module is `GnomeGardenWeb.ClientPortalAuth` with function `:require_client_user`.

---

## Section 2: Routes & Pages

All portal routes live under `/portal`, isolated from internal routes.

### Public Routes

```elixir
scope "/portal" do
  pipe_through :browser

  # Magic link login entry (email form)
  get "/login", GnomeGardenWeb.ClientPortal.SessionController, :new
  post "/login", GnomeGardenWeb.ClientPortal.SessionController, :create

  # AshAuthentication magic link callback — MUST be explicitly declared
  # Pattern mirrors the staff magic_sign_in_route in the existing router
  magic_sign_in_route GnomeGarden.Accounts.ClientUser, :magic_link,
    path: "/portal/sign-in"
end
```

### Authenticated Routes

```elixir
ash_authentication_live_session :client_portal,
  on_mount: [{GnomeGardenWeb.ClientPortalAuth, :require_client_user}] do

  live "/portal", GnomeGardenWeb.ClientPortal.DashboardLive, :index
  live "/portal/invoices", GnomeGardenWeb.ClientPortal.InvoiceLive.Index, :index
  live "/portal/invoices/:id", GnomeGardenWeb.ClientPortal.InvoiceLive.Show, :show
  live "/portal/agreements", GnomeGardenWeb.ClientPortal.AgreementLive.Index, :index
  live "/portal/agreements/:id", GnomeGardenWeb.ClientPortal.AgreementLive.Show, :show
end
```

### Pages

**Dashboard (`/portal`)**
- Outstanding balance (sum of balance_amount on issued/partial invoices)
- Recent invoices table (last 5, with status badges)
- Active agreements count

**Invoice List (`/portal/invoices`)**
- Table: invoice number, issued date, due date, total amount, balance due, status badge
- Filter by status (all / outstanding / paid)
- Link to invoice detail

**Invoice Detail (`/portal/invoices/:id`)**
- Invoice header: number, issued date, due date, status
- Line items table: description, quantity, rate, amount
- Subtotal, tax, total
- Balance due (prominent)
- **Mercury ACH section**: Bank (Mercury), Account #, Routing #, Reference (invoice number)
- **"Pay by card" button**: links to `stripe_payment_url` if present; adds 3% fee notice
- **Download PDF** button (links to existing `/finance/invoices/:id/export/pdf` — reuse existing export)

**Agreement List (`/portal/agreements`)**
- Table: name, type, billing model, status, contract value (fixed-fee only)
- Only active agreements shown

**Agreement Detail (`/portal/agreements/:id`)**
- Agreement name, description, type, billing model
- Contract value (fixed-fee) or bill rate (T&M)
- Payment terms
- Linked invoices table (subset of invoice list for this agreement)

---

## Section 3: Payments

### Mercury ACH (primary)

Displayed on every invoice detail page. No integration needed — reads from existing `Application.get_env(:gnome_garden, :mercury_payment_info)` config (same as invoice email).

### Stripe (secondary)

**Dependency:** `stripity_stripe` hex package.

**New config (runtime.exs):**
```elixir
# Follow the existing pattern of raise guards for required production secrets:
if config_env() == :prod do
  stripe_secret_key =
    System.get_env("STRIPE_SECRET_KEY") ||
      raise "environment variable STRIPE_SECRET_KEY is missing"

  stripe_webhook_secret =
    System.get_env("STRIPE_WEBHOOK_SECRET") ||
      raise "environment variable STRIPE_WEBHOOK_SECRET is missing"

  config :stripity_stripe, api_key: stripe_secret_key
  config :gnome_garden, stripe_webhook_secret: stripe_webhook_secret
end
```

**New module:** `lib/garden/payments/stripe_client.ex`
```elixir
defmodule GnomeGarden.Payments.StripeClient do
  # create_payment_link(invoice) → {:ok, url} | {:error, reason}
  # Builds a Stripe Payment Link for invoice.total_amount + 3% fee
  # Metadata includes invoice_id for webhook matching
end
```

**Invoice issue hook:** Implemented as an `Ash.Resource.Change` module attached to the `:issue` action on `Invoice`. After the state transition succeeds, the change calls `StripeClient.create_payment_link/1` and writes the result back to the changeset.

```elixir
# lib/garden/finance/changes/generate_stripe_payment_link.ex
defmodule GnomeGarden.Finance.Changes.GenerateStripePaymentLink do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      case GnomeGarden.Payments.StripeClient.create_payment_link(invoice) do
        {:ok, url} ->
          Ash.update!(invoice, %{stripe_payment_url: url},
            action: :update, domain: GnomeGarden.Finance, authorize?: false)
          {:ok, invoice}
        {:error, reason} ->
          Logger.warning("GenerateStripePaymentLink: #{inspect(reason)}")
          {:ok, invoice}  # non-fatal — ACH still works, button is hidden when nil
      end
    end)
  end
end
```

Add `change GnomeGarden.Finance.Changes.GenerateStripePaymentLink` to the `:issue` action in `lib/garden/finance/invoice.ex`.

**Stripe Webhook:**
- Route: `POST /webhooks/stripe` — added inside the **existing** `/webhooks` scope in `router.ex`, which already uses the `:webhooks` pipeline (skips CSRF, caches raw body for HMAC). Do NOT create a new scope.
- Controller: `lib/garden_web/controllers/stripe_webhook_controller.ex`
- Verifies HMAC signature using `STRIPE_WEBHOOK_SECRET` (same pattern as `MercuryWebhookController`)
- Handles `checkout.session.completed` → looks up invoice by `session.metadata["invoice_id"]` → calls `Finance.mark_paid(invoice, authorize?: false)`
- Returns 200 for all unhandled event types (Stripe requires 2xx or it retries)

**Fee passing:** Stripe Payment Link created with a second line item: "Card processing fee (3%)" = `round(total_amount * 0.03)`. Client sees the breakdown at checkout.

---

## Section 4: Data Model

### New Table: `client_users`

```sql
CREATE TABLE client_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  inserted_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  UNIQUE (email, organization_id)  -- not email alone: one person may contact multiple client orgs
);

CREATE TABLE client_user_tokens (
  -- generated automatically by AshAuthentication for ClientUserToken resource
);
```

Generated via Ash migration: `mix ash_postgres.generate_migrations --name add_client_users`

### Modified Table: `finance_invoices`

```sql
ALTER TABLE finance_invoices ADD COLUMN stripe_payment_url varchar;
```

### No Other Migrations

All portal pages read from existing `finance_invoices`, `commercial_agreements`, and `organizations` tables.

---

## Section 5: Multi-Tenant Security

**Ash policies on `Invoice` (portal read action):**
```elixir
read :portal_index do
  filter expr(organization_id == ^actor.organization_id)
  prepare build(load: [:invoice_lines, :agreement, :organization])
end

read :portal_show do
  filter expr(organization_id == ^actor.organization_id)
  get? true
  prepare build(load: [:invoice_lines, :agreement, :organization])
end
```

Same pattern on `Agreement` (load `:payment_schedule_items` on show). URL tampering (e.g., changing invoice ID) returns a not-found error, never returns another org's data.

**Portal LiveViews:**
- Always pass `actor: socket.assigns.current_client_user` to Ash queries
- Never call internal Finance functions that lack portal-scoped read actions
- `require_client_user` mount hook redirects unauthenticated visitors to `/portal/login`

**Staff isolation:** Staff cannot log into the portal with their staff credentials. Separate auth strategies, separate session cookies (`_gnome_garden_client_key` vs `_gnome_garden_key`).

---

## New Files

```
lib/garden/accounts/client_user.ex
lib/garden/accounts/client_user_token.ex           ← required by AshAuthentication
lib/garden/accounts/client_user/senders/send_magic_link_email.ex
lib/garden/accounts/client_user/senders/send_client_invite_email.ex
lib/garden/finance/changes/generate_stripe_payment_link.ex
lib/garden/payments/stripe_client.ex
lib/garden_web/controllers/client_portal/session_controller.ex
lib/garden_web/controllers/stripe_webhook_controller.ex
lib/garden_web/live/client_portal/dashboard_live.ex
lib/garden_web/live/client_portal/invoice_live/index.ex
lib/garden_web/live/client_portal/invoice_live/show.ex
lib/garden_web/live/client_portal/agreement_live/index.ex
lib/garden_web/live/client_portal/agreement_live/show.ex
lib/garden_web/live/client_portal_auth.ex          ← GnomeGardenWeb.ClientPortalAuth with require_client_user/2
```

## Modified Files

```
lib/garden/accounts.ex                             ← register ClientUser in domain
lib/garden/finance/invoice.ex                      ← add stripe_payment_url attr + portal read actions + Stripe hook on issue
lib/garden/commercial/agreement.ex                 ← add portal read actions
lib/garden_web/router.ex                           ← add /portal routes + /webhooks/stripe
lib/garden_web/live/operations/organization_live/show.ex  ← add "Invite to portal" button
config/runtime.exs                                 ← STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET
mix.exs                                            ← add stripity_stripe dependency
```

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Stripe API down when issuing invoice | Log warning, continue — ACH still works, `stripe_payment_url` is nil, "Pay by card" button hidden |
| Stripe webhook signature invalid | Return 401, log warning |
| Client self-serve email not found | Generic "check your email" response — no leak |
| Client tries to access another org's invoice via URL | Ash policy returns not-found |
| Invoice already paid when Stripe webhook fires | Idempotent — `mark_paid` on already-paid invoice is a no-op |

---

## Testing

| File | Coverage |
|---|---|
| `test/garden/accounts/client_user_test.exs` | Magic link registration, invite action, self-serve lookup |
| `test/garden/payments/stripe_client_test.exs` | Payment link creation (mocked Stripe API) |
| `test/garden_web/controllers/stripe_webhook_controller_test.exs` | Signature verification, checkout.session.completed → invoice paid, unknown events return 200 |
| `test/garden_web/live/client_portal/dashboard_live_test.exs` | Auth redirect, outstanding balance display |
| `test/garden_web/live/client_portal/invoice_live_test.exs` | Invoice list scoped to org, invoice detail shows ACH + Stripe button, cross-org access blocked |
| `test/garden_web/live/client_portal/agreement_live_test.exs` | Agreement list scoped to org, cross-org access blocked |

---

## Production Checklist

- [ ] Set `STRIPE_SECRET_KEY` in production env
- [ ] Set `STRIPE_WEBHOOK_SECRET` in production env
- [ ] Register `/webhooks/stripe` in Stripe dashboard
- [ ] Configure Stripe webhook to send `checkout.session.completed`
- [ ] Verify portal routes accessible at production domain
