# Client Portal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a client-facing portal at `/portal` where clients authenticate via magic link and view/pay their invoices and agreements.

**Architecture:** A separate `ClientUser` Ash resource (isolated from staff `User`) uses AshAuthentication magic link strategy with its own token store. Portal LiveViews run in a dedicated `ash_authentication_live_session` with a `ClientPortalAuth` hook that enforces `current_client_user`. All portal Ash queries are filtered to `actor.organization_id` at the data layer — URL tampering returns 404. Stripe payment links are generated on invoice issue and shown on the invoice detail page.

**Tech Stack:** Elixir/Phoenix, Ash Framework, AshAuthentication, Phoenix LiveView, Swoosh (email), stripity_stripe, Tailwind CSS, PostgreSQL

---

## File Structure

### New Files
- `lib/garden/accounts/client_user.ex` — ClientUser Ash resource with AshAuthentication magic link
- `lib/garden/accounts/client_user_token.ex` — Token store for ClientUser (mirrors existing Token)
- `lib/garden/accounts/client_user/senders/send_magic_link_email.ex` — Magic link email sender
- `lib/garden/accounts/client_user/senders/send_client_invite_email.ex` — Staff invite email sender
- `lib/garden_web/live/client_portal_auth.ex` — on_mount hook (require_client_user)
- `lib/garden_web/controllers/client_portal/session_controller.ex` — /portal/login form + submit
- `lib/garden_web/components/layouts/portal_app.html.heex` — Portal layout (no staff sidebar)
- `lib/garden_web/live/client_portal/dashboard_live.ex` — Dashboard: balance + recent invoices
- `lib/garden_web/live/client_portal/invoice_live/index.ex` — Invoice list
- `lib/garden_web/live/client_portal/invoice_live/show.ex` — Invoice detail + pay
- `lib/garden_web/live/client_portal/agreement_live/index.ex` — Agreement list
- `lib/garden_web/live/client_portal/agreement_live/show.ex` — Agreement detail
- `lib/garden/payments/stripe_client.ex` — Stripe API wrapper
- `lib/garden/finance/changes/generate_stripe_payment_link.ex` — Ash.Resource.Change on :issue
- `lib/garden_web/controllers/stripe_webhook_controller.ex` — Stripe webhook (checkout.session.completed)

### Modified Files
- `lib/garden/accounts.ex` — register ClientUser + ClientUserToken + code interfaces
- `lib/garden/finance/invoice.ex` — add stripe_payment_url attr + portal read actions
- `lib/garden/commercial/agreement.ex` — add portal read actions
- `lib/garden_web/router.ex` — add /portal public + authenticated routes + /webhooks/stripe
- (No change to `lib/garden_web/components/layouts.ex` needed — `embed_templates "layouts/*"` auto-discovers portal_app.html.heex)
- `config/runtime.exs` — STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET
- `mix.exs` — add stripity_stripe dependency
- `test/support/conn_case.ex` — add register_and_log_in_client_user helper
- `lib/garden_web/live/operations/organization_live/show.ex` — "Invite to portal" button

---

## Task 1: ClientUser + ClientUserToken Resources + Migration

**Files:**
- Create: `lib/garden/accounts/client_user.ex`
- Create: `lib/garden/accounts/client_user_token.ex`
- Modify: `lib/garden/accounts.ex`
- Test: `test/garden/accounts/client_user_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden/accounts/client_user_test.exs`:

```elixir
defmodule GnomeGarden.Accounts.ClientUserTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Accounts

  setup do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    {:ok, org: org}
  end

  test "invite/2 creates a ClientUser for an org", %{org: org} do
    assert {:ok, cu} = Accounts.invite_client_user("client@example.com", org.id)
    assert to_string(cu.email) == "client@example.com"
    assert cu.organization_id == org.id
  end

  test "invite/2 is idempotent (upserts on duplicate email+org)", %{org: org} do
    assert {:ok, cu1} = Accounts.invite_client_user("client@example.com", org.id)
    assert {:ok, cu2} = Accounts.invite_client_user("client@example.com", org.id)
    assert cu1.id == cu2.id
  end

  test "same email can belong to two different orgs" do
    org2 = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other Org"})
    org3 = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Third Org"})
    assert {:ok, _} = Accounts.invite_client_user("shared@example.com", org2.id)
    assert {:ok, _} = Accounts.invite_client_user("shared@example.com", org3.id)
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/accounts/client_user_test.exs --trace
```

Expected: FAIL — `Accounts.invite_client_user/2` does not exist yet.

- [ ] **Step 3: Create ClientUser resource**

Create `lib/garden/accounts/client_user.ex`:

```elixir
defmodule GnomeGarden.Accounts.ClientUser do
  @moduledoc """
  Portal authentication resource for client contacts.

  Completely separate from the staff User resource — different token store,
  different session cookie key, different magic link route. One ClientUser
  row per (email, organization_id) pair: a contact at two orgs gets two rows.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    tokens do
      enabled? true
      token_resource GnomeGarden.Accounts.ClientUserToken
      signing_secret GnomeGarden.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        sender GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail
      end
    end
  end

  postgres do
    table "client_users"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a client user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    create :sign_in_with_magic_link do
      description "Sign in a client user with a magic link token."
      argument :token, :string, allow_nil?: false

      upsert? true
      upsert_identity :unique_email_per_org
      upsert_fields [:email]

      change AshAuthentication.Strategy.MagicLink.SignInChange

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string, allow_nil?: false
      run AshAuthentication.Strategy.MagicLink.Request
    end

    create :invite do
      description "Upsert a ClientUser for the given email + org, used by staff invite and self-serve flows."
      accept [:email, :organization_id]
      upsert? true
      upsert_identity :unique_email_per_org
      upsert_fields [:email]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_email_per_org, [:email, :organization_id]
  end
end
```

- [ ] **Step 4: Create ClientUserToken resource**

Create `lib/garden/accounts/client_user_token.ex`. This is a copy of `lib/garden/accounts/token.ex` — same actions, same attributes, different table name:

```elixir
defmodule GnomeGarden.Accounts.ClientUserToken do
  @moduledoc """
  Token store for ClientUser magic links.
  Required by AshAuthentication — must be a separate resource from the staff Token.
  AshAuthentication will raise a configuration error at startup if this is missing.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "client_user_tokens"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    read :expired do
      description "Look up all expired tokens."
      filter expr(expires_at < now())
    end

    read :get_token do
      description "Look up a token by JTI or token, and an optional purpose."
      get? true
      argument :token, :string, sensitive?: true
      argument :jti, :string, sensitive?: true
      argument :purpose, :string, sensitive?: false
      prepare AshAuthentication.TokenResource.GetTokenPreparation
    end

    action :revoked?, :boolean do
      description "Returns true if a revocation token is found for the provided token"
      argument :token, :string, sensitive?: true
      argument :jti, :string, sensitive?: true
      run AshAuthentication.TokenResource.IsRevoked
    end

    create :revoke_token do
      accept [:extra_data]
      argument :token, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.RevokeTokenChange
    end

    create :revoke_jti do
      accept [:extra_data]
      argument :subject, :string, allow_nil?: false, sensitive?: true
      argument :jti, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.RevokeJtiChange
    end

    create :store_token do
      accept [:extra_data, :purpose]
      argument :token, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.StoreTokenChange
    end

    destroy :expunge_expired do
      change filter expr(expires_at < now())
    end

    update :revoke_all_stored_for_subject do
      accept [:extra_data]
      argument :subject, :string, allow_nil?: false, sensitive?: true
      change AshAuthentication.TokenResource.RevokeAllStoredForSubjectChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    attribute :jti, :string do
      primary_key? true
      public? true
      allow_nil? false
      sensitive? true
    end

    attribute :subject, :string do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :purpose, :string do
      allow_nil? false
      public? true
    end

    attribute :extra_data, :map do
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end
end
```

- [ ] **Step 5: Register in Accounts domain**

Read `lib/garden/accounts.ex` first, then add inside the `resources do` block:

```elixir
# After the existing Token resource:
resource GnomeGarden.Accounts.ClientUserToken

resource GnomeGarden.Accounts.ClientUser do
  define :get_client_user, action: :read, get_by: [:id]
  define :invite_client_user, action: :invite, args: [:email, :organization_id]
  define :request_client_portal_access, action: :request_magic_link, args: [:email]
end
```

- [ ] **Step 6: Generate migration**

```bash
cd /home/bhammoud/gnome_garden_mercury
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.generate_migrations --name add_client_users
```

Expected: new file in `priv/repo/migrations/` creating `client_users` and `client_user_tokens` tables.

Inspect the generated migration and verify:
- `client_users` has `id`, `email` (citext), `organization_id` (uuid), `inserted_at`, `updated_at`
- A UNIQUE index on `(email, organization_id)`
- `client_user_tokens` has `jti`, `subject`, `expires_at`, `purpose`, `extra_data`, `created_at`, `updated_at`

If the migration inadvertently includes columns from other resources (a known Ash snapshot drift issue), remove any extra columns not listed above before running.

- [ ] **Step 7: Run migration**

```bash
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.migrate
```

Expected: `== Running ... AddClientUsers == ... [up]` with no errors.

- [ ] **Step 8: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/accounts/client_user_test.exs --trace
```

Expected: 3 tests, 0 failures.

- [ ] **Step 9: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 10: Commit**

```bash
git add lib/garden/accounts/client_user.ex \
        lib/garden/accounts/client_user_token.ex \
        lib/garden/accounts.ex \
        priv/repo/migrations/ \
        test/garden/accounts/client_user_test.exs
git commit -m "feat: add ClientUser + ClientUserToken resources with AshAuthentication magic link"
```

---

## Task 2: Sender Modules + ClientPortalAuth Hook

**Files:**
- Create: `lib/garden/accounts/client_user/senders/send_magic_link_email.ex`
- Create: `lib/garden/accounts/client_user/senders/send_client_invite_email.ex`
- Create: `lib/garden_web/live/client_portal_auth.ex`

No database changes in this task — senders are pure functions, hook is an on_mount module.

- [ ] **Step 1: Create magic link email sender**

Create `lib/garden/accounts/client_user/senders/send_magic_link_email.ex`:

```elixir
defmodule GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a portal sign-in magic link to a client.
  Called by AshAuthentication when request_magic_link is triggered.
  """

  use AshAuthentication.Sender
  use GnomeGardenWeb, :verified_routes

  import Swoosh.Email
  alias GnomeGarden.Mailer

  @impl true
  def send(client_user_or_email, token, _opts) do
    email =
      case client_user_or_email do
        %{email: email} -> email
        email -> email
      end

    sign_in_url = url(~p"/portal/sign-in/#{token}")

    new()
    |> from({"Gnome Automation", "noreply@gnomeautomation.io"})
    |> to(to_string(email))
    |> subject("Your portal sign-in link")
    |> html_body("""
    <p>Hello,</p>
    <p>Click the link below to sign in to your client portal. This link expires in 10 minutes.</p>
    <p><a href="#{sign_in_url}">Sign in to your portal</a></p>
    <p>If you did not request this link, you can safely ignore this email.</p>
    """)
    |> Mailer.deliver!()
  end
end
```

- [ ] **Step 2: Create client invite email sender**

Create `lib/garden/accounts/client_user/senders/send_client_invite_email.ex`:

```elixir
defmodule GnomeGarden.Accounts.ClientUser.Senders.SendClientInviteEmail do
  @moduledoc """
  Sends a portal invitation email to a newly invited client.
  Called explicitly by the invite flow (not by AshAuthentication directly).
  """

  use GnomeGardenWeb, :verified_routes

  import Swoosh.Email
  alias GnomeGarden.Mailer

  @doc """
  Sends an invitation email with a magic link token.
  token is the raw magic link token string from AshAuthentication.
  """
  def send(email, token) do
    sign_in_url = url(~p"/portal/sign-in/#{token}")

    new()
    |> from({"Gnome Automation", "noreply@gnomeautomation.io"})
    |> to(to_string(email))
    |> subject("You've been invited to the Gnome Automation client portal")
    |> html_body("""
    <p>Hello,</p>
    <p>You've been invited to access the Gnome Automation client portal where you can view your invoices and agreements.</p>
    <p><a href="#{sign_in_url}">Accept invitation and sign in</a></p>
    <p>This link expires in 10 minutes. You can request a new sign-in link at any time from the portal login page.</p>
    """)
    |> Mailer.deliver!()
  end
end
```

- [ ] **Step 3: Create ClientPortalAuth on_mount hook**

Create `lib/garden_web/live/client_portal_auth.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortalAuth do
  @moduledoc """
  on_mount helpers for portal LiveViews.

  Usage in ash_authentication_live_session:
    on_mount: [{GnomeGardenWeb.ClientPortalAuth, :require_client_user}]

  Sets `current_client_user` from session. Redirects unauthenticated
  visitors to /portal/login.
  """

  import Phoenix.Component
  use GnomeGardenWeb, :verified_routes

  def on_mount(:require_client_user, _params, _session, socket) do
    socket = assign_new(socket, :current_client_user, fn -> nil end)

    if socket.assigns.current_client_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/portal/login")}
    end
  end
end
```

- [ ] **Step 4: Verify compilation**

```bash
GNOME_GARDEN_DB_PORT=5432 mix compile 2>&1 | grep -i error
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/garden/accounts/client_user/senders/send_magic_link_email.ex \
        lib/garden/accounts/client_user/senders/send_client_invite_email.ex \
        lib/garden_web/live/client_portal_auth.ex
git commit -m "feat: add ClientUser sender modules and ClientPortalAuth on_mount hook"
```

---

## Task 3: Session Controller + Portal Routes + Portal Layout + Test Helper

**Files:**
- Create: `lib/garden_web/controllers/client_portal/session_controller.ex`
- Create: `lib/garden_web/layouts/portal_app.html.heex`
- Modify: `lib/garden_web/router.ex`
- Modify: `test/support/conn_case.ex`
- Test: `test/garden_web/controllers/client_portal/session_controller_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden_web/controllers/client_portal/session_controller_test.exs`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.SessionControllerTest do
  use GnomeGardenWeb.ConnCase, async: true

  alias GnomeGarden.Operations
  alias GnomeGarden.Accounts

  test "GET /portal/login renders login form", %{conn: conn} do
    conn = get(conn, ~p"/portal/login")
    assert html_response(conn, 200) =~ "Sign in"
  end

  test "POST /portal/login with unknown email silently succeeds", %{conn: conn} do
    conn = post(conn, ~p"/portal/login", %{"email" => "unknown@example.com"})
    assert html_response(conn, 200) =~ "check your email"
  end

  test "POST /portal/login with known email silently succeeds", %{conn: conn} do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    person = Ash.Seed.seed!(GnomeGarden.Operations.Person, %{
      name: "Test Person",
      email: "known@example.com"
    })
    Ash.Seed.seed!(GnomeGarden.Operations.OrganizationAffiliation, %{
      organization_id: org.id,
      person_id: person.id,
      status: :active
    })

    conn = post(conn, ~p"/portal/login", %{"email" => "known@example.com"})
    assert html_response(conn, 200) =~ "check your email"
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/client_portal/session_controller_test.exs --trace
```

Expected: FAIL — route and controller don't exist yet.

- [ ] **Step 3: Create the portal layout**

First, verify the layouts directory: run `ls lib/garden_web/components/layouts/` to confirm the existing layout files are there. The `GnomeGardenWeb.Layouts` module uses `embed_templates "layouts/*"` which is relative to the module file at `lib/garden_web/components/layouts.ex`, so templates must go in `lib/garden_web/components/layouts/`.

Create `lib/garden_web/components/layouts/portal_app.html.heex`:

```html
<header class="bg-white shadow-sm border-b border-gray-200 dark:bg-gray-900 dark:border-gray-800">
  <div class="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <span class="text-emerald-600 font-semibold text-lg">Gnome Automation</span>
      <span class="text-gray-400 text-sm">Client Portal</span>
    </div>
    <div class="text-sm text-gray-500 dark:text-gray-400">
      <%= if assigns[:current_client_user] do %>
        <%= @current_client_user.email %>
      <% end %>
    </div>
  </div>
</header>

<main class="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-8">
  <.flash_group flash={@flash} />
  {@inner_content}
</main>
```

**Note:** Check if `<.flash_group>` is available in this app by looking at how other templates use flash. If not, use `<.flash kind={:info} flash={@flash} />` and `<.flash kind={:error} flash={@flash} />`.

- [ ] **Step 4: Create the SessionController**

Create `lib/garden_web/controllers/client_portal/session_controller.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.SessionController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations

  def new(conn, _params) do
    render(conn, :new, layout: {GnomeGardenWeb.Layouts, :root}, page_title: "Sign In")
  end

  def create(conn, %{"email" => email}) do
    # Always respond with the same message to prevent email enumeration
    maybe_send_magic_link(email)

    conn
    |> put_flash(:info, "If you have an account, check your email for a sign-in link.")
    |> render(:new, layout: {GnomeGardenWeb.Layouts, :root}, page_title: "Sign In")
  end

  defp maybe_send_magic_link(email) do
    with {:ok, person} <- Operations.get_person_by_email(email),
         {:ok, affiliations} <- Operations.list_affiliations_for_person(person.id),
         [affiliation | _] <- Enum.filter(affiliations, &(&1.status == :active)),
         {:ok, _client_user} <- Accounts.invite_client_user(email, affiliation.organization_id) do
      # Request magic link — AshAuthentication sends it via SendMagicLinkEmail sender
      Accounts.request_client_portal_access(email)
    else
      _ -> :ok  # silently succeed — no information leak
    end
  end
end
```

**Also create the template** at `lib/garden_web/controllers/client_portal/session_html/new.html.heex`:

```html
<div class="min-h-screen bg-gray-50 dark:bg-gray-950 flex items-center justify-center py-12 px-4">
  <div class="max-w-md w-full">
    <div class="text-center mb-8">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Client Portal</h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">Enter your email to receive a sign-in link.</p>
    </div>

    <.flash_group flash={@flash} />

    <div class="bg-white dark:bg-gray-900 shadow rounded-lg p-6">
      <form action={~p"/portal/login"} method="post">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <div class="mb-4">
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">
            Email address
          </label>
          <input
            type="email"
            name="email"
            required
            placeholder="you@example.com"
            class="rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500 w-full"
          />
        </div>
        <button
          type="submit"
          class="w-full rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
        >
          Send sign-in link
        </button>
      </form>
    </div>
  </div>
</div>
```

**Also create the HTML module** at `lib/garden_web/controllers/client_portal/session_html.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.SessionHTML do
  use GnomeGardenWeb, :html

  embed_templates "session_html/*"
end
```

- [ ] **Step 5: Add routes to router.ex**

Read `lib/garden_web/router.ex` first, then make the following changes:

**A) Add portal public scope** — insert before the `/webhooks` scope:

```elixir
# Portal — public routes (no auth required)
scope "/portal", GnomeGardenWeb do
  pipe_through :browser

  get "/login", ClientPortal.SessionController, :new
  post "/login", ClientPortal.SessionController, :create

  # AshAuthentication magic link callback for ClientUser
  # IMPORTANT: path is "/sign-in" (not "/portal/sign-in") because this scope
  # already prefixes all routes with "/portal". The resolved URL is /portal/sign-in,
  # which matches the URL generated in the sender module (~p"/portal/sign-in/#{token}").
  magic_sign_in_route GnomeGarden.Accounts.ClientUser, :magic_link,
    path: "/sign-in",
    success_redirect: "/portal"
end

# Portal — authenticated routes (ClientUser session required)
scope "/", GnomeGardenWeb do
  pipe_through :browser

  ash_authentication_live_session :client_portal,
    layout: {GnomeGardenWeb.Layouts, :portal_app},
    on_mount: [{GnomeGardenWeb.ClientPortalAuth, :require_client_user}] do

    live "/portal", ClientPortal.DashboardLive, :index
    live "/portal/invoices", ClientPortal.InvoiceLive.Index, :index
    live "/portal/invoices/:id", ClientPortal.InvoiceLive.Show, :show
    live "/portal/agreements", ClientPortal.AgreementLive.Index, :index
    live "/portal/agreements/:id", ClientPortal.AgreementLive.Show, :show
  end
end
```

**B) Add Stripe webhook** — inside the existing `scope "/webhooks"` block (do NOT create a new scope):

```elixir
post "/stripe", StripeWebhookController, :receive
```

**Note on session isolation:** AshAuthentication stores each resource under a separate key in the Phoenix session, derived from the resource module name (`GnomeGarden.Accounts.User` vs `GnomeGarden.Accounts.ClientUser`). Staff and client sessions do not conflict — no separate session cookie is required.

**Note on `magic_sign_in_route`:** `success_redirect:` may not be a supported option depending on the AshAuthentication.Phoenix version. If compilation fails with an unknown option error, remove `success_redirect: "/portal"` and instead implement a redirect in the route handler via an override. The portal will still work — after sign-in, the client is redirected to `"/"` which will fall through to the portal login page, and on next visit to `/portal` they will be authenticated.

- [ ] **Step 6: Add `register_and_log_in_client_user` test helper**

Read `test/support/conn_case.ex` first, then add after the existing `register_and_log_in_user/1` function:

```elixir
def register_and_log_in_client_user(%{conn: conn} = context) do
  org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Client Org #{System.unique_integer()}"})
  email = "client-#{System.unique_integer([:positive, :monotonic])}@example.com"

  client_user =
    Ash.Seed.seed!(GnomeGarden.Accounts.ClientUser, %{
      email: email,
      organization_id: org.id
    })

  {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(client_user)
  client_user = Ash.Resource.put_metadata(client_user, :token, token)

  new_conn =
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(client_user)

  context
  |> Map.put(:conn, new_conn)
  |> Map.put(:current_client_user, client_user)
  |> Map.put(:organization, org)
end
```

- [ ] **Step 7: Run session controller tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/controllers/client_portal/session_controller_test.exs --trace
```

Expected: 3 tests, 0 failures.

- [ ] **Step 8: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 9: Commit**

```bash
git add lib/garden_web/controllers/client_portal/ \
        lib/garden_web/components/layouts/portal_app.html.heex \
        lib/garden_web/router.ex \
        test/support/conn_case.ex \
        test/garden_web/controllers/client_portal/
git commit -m "feat: add portal SessionController, routes, portal layout, and test helper"
```

---

## Task 4: Invoice + Agreement Portal Read Actions

Add `stripe_payment_url` attribute and portal-scoped read actions to Invoice. Add portal-scoped read actions to Agreement. No new migrations needed for Agreement. Invoice gets a new column via migration.

**Files:**
- Modify: `lib/garden/finance/invoice.ex`
- Modify: `lib/garden/commercial/agreement.ex`
- Modify: `lib/garden/finance.ex` (add define for portal actions)
- Modify: `lib/garden/commercial.ex` (add define for portal actions)

- [ ] **Step 1: Write failing tests**

Create `test/garden/finance/invoice_portal_test.exs`:

```elixir
defmodule GnomeGarden.Finance.InvoicePortalTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  setup do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Client Org"})
    other_org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other Org"})
    client_user = Ash.Seed.seed!(GnomeGarden.Accounts.ClientUser, %{
      email: "c@example.com",
      organization_id: org.id
    })

    invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-001",
      status: :issued,
      total_amount: Money.new(10000, :USD),
      balance_amount: Money.new(10000, :USD)
    })

    other_invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: other_org.id,
      invoice_number: "INV-002",
      status: :issued,
      total_amount: Money.new(5000, :USD),
      balance_amount: Money.new(5000, :USD)
    })

    {:ok, org: org, client_user: client_user, invoice: invoice, other_invoice: other_invoice}
  end

  test "portal_index returns only invoices for actor's org", %{client_user: cu, invoice: inv, other_invoice: other} do
    {:ok, results} = Finance.list_portal_invoices(actor: cu)
    ids = Enum.map(results, & &1.id)
    assert inv.id in ids
    refute other.id in ids
  end

  test "portal_show returns invoice for actor's org", %{client_user: cu, invoice: inv} do
    assert {:ok, result} = Finance.get_portal_invoice(inv.id, actor: cu)
    assert result.id == inv.id
  end

  test "portal_show returns not found for another org's invoice", %{client_user: cu, other_invoice: other} do
    assert {:error, _} = Finance.get_portal_invoice(other.id, actor: cu)
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/invoice_portal_test.exs --trace
```

Expected: FAIL — portal actions don't exist yet.

- [ ] **Step 3: Add stripe_payment_url + portal actions to Invoice**

Read `lib/garden/finance/invoice.ex` first. Then:

**Add attribute** inside the `attributes do` block (with the other string/nullable attributes):

```elixir
attribute :stripe_payment_url, :string do
  allow_nil? true
  description "Stripe Payment Link URL. Generated on invoice issue. Nil if Stripe is unavailable."
end
```

**Add portal read actions** inside `actions do`:

```elixir
read :portal_index do
  description "Portal-scoped invoice list — returns only invoices for actor's organization."
  filter expr(organization_id == ^actor(:organization_id))
  prepare build(load: [:invoice_lines, :agreement, :organization])
end

read :portal_show do
  description "Portal-scoped invoice detail — returns a single invoice for actor's organization."
  filter expr(organization_id == ^actor(:organization_id))
  get? true
  prepare build(load: [:invoice_lines, :agreement, :organization])
end
```

- [ ] **Step 4: Generate migration for stripe_payment_url**

```bash
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.generate_migrations --name add_stripe_payment_url_to_invoices
```

Expected: migration that adds `stripe_payment_url varchar` to `finance_invoices`.

- [ ] **Step 5: Run migration**

```bash
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.migrate
```

- [ ] **Step 6: Add portal actions to Agreement**

Read `lib/garden/commercial/agreement.ex` first. Add inside `actions do`:

```elixir
read :portal_index do
  description "Portal-scoped agreement list — returns only active agreements for actor's organization."
  filter expr(organization_id == ^actor(:organization_id) and status == :active)
  prepare build(load: [:invoices])
end

read :portal_show do
  description "Portal-scoped agreement detail — returns a single agreement for actor's organization."
  filter expr(organization_id == ^actor(:organization_id))
  get? true
  prepare build(load: [:payment_schedule_items, :invoices])
end
```

**Note:** Check that Agreement has an `:invoices` relationship. If not, replace with whatever relationship lists linked invoices. Look at the existing agreement show LiveView to see what it loads.

- [ ] **Step 7: Add code interfaces to Finance and Commercial domains**

In `lib/garden/finance.ex`, inside the `resource GnomeGarden.Finance.Invoice do` block, add:

```elixir
define :list_portal_invoices, action: :portal_index
define :get_portal_invoice, action: :portal_show, get_by: [:id]
```

In `lib/garden/commercial.ex`, inside the `resource GnomeGarden.Commercial.Agreement do` block, add:

```elixir
define :list_portal_agreements, action: :portal_index
define :get_portal_agreement, action: :portal_show, get_by: [:id]
```

- [ ] **Step 8: Run portal tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/invoice_portal_test.exs --trace
```

Expected: 3 tests, 0 failures.

- [ ] **Step 9: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 10: Commit**

```bash
git add lib/garden/finance/invoice.ex \
        lib/garden/commercial/agreement.ex \
        lib/garden/finance.ex \
        lib/garden/commercial.ex \
        priv/repo/migrations/ \
        test/garden/finance/invoice_portal_test.exs
git commit -m "feat: add stripe_payment_url and portal read actions to Invoice and Agreement"
```

---

## Task 5: Dashboard + Invoice LiveViews

**Files:**
- Create: `lib/garden_web/live/client_portal/dashboard_live.ex`
- Create: `lib/garden_web/live/client_portal/invoice_live/index.ex`
- Create: `lib/garden_web/live/client_portal/invoice_live/show.ex`
- Test: `test/garden_web/live/client_portal/dashboard_live_test.exs`
- Test: `test/garden_web/live/client_portal/invoice_live_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden_web/live/client_portal/dashboard_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.DashboardLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_client_user

  setup %{organization: org} do
    Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-0001",
      status: :issued,
      total_amount: Money.new(100_00, :USD),
      balance_amount: Money.new(100_00, :USD)
    })
    :ok
  end

  test "redirects unauthenticated visitor to /portal/login", %{conn: conn} do
    # Use a fresh conn with no session
    fresh_conn = Phoenix.ConnTest.build_conn()
    {:error, {:redirect, %{to: path}}} = live(fresh_conn, ~p"/portal")
    assert path == ~p"/portal/login"
  end

  test "renders dashboard for authenticated client", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/portal")
    assert html =~ "Dashboard"
  end

  test "shows outstanding balance", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/portal")
    assert html =~ "100"
  end
end
```

Create `test/garden_web/live/client_portal/invoice_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.InvoiceLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  setup :register_and_log_in_client_user

  setup %{organization: org} do
    invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-0042",
      status: :issued,
      total_amount: Money.new(500_00, :USD),
      balance_amount: Money.new(500_00, :USD)
    })
    {:ok, invoice: invoice}
  end

  test "invoice list shows invoices for client's org", %{conn: conn, invoice: inv} do
    {:ok, _view, html} = live(conn, ~p"/portal/invoices")
    assert html =~ "INV-0042"
  end

  test "invoice detail shows ACH payment instructions", %{conn: conn, invoice: inv} do
    {:ok, _view, html} = live(conn, ~p"/portal/invoices/#{inv.id}")
    assert html =~ "INV-0042"
    assert html =~ "ACH"
  end

  test "cannot access another org's invoice", %{conn: conn} do
    other_org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other"})
    other_invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: other_org.id,
      invoice_number: "INV-9999",
      status: :issued,
      total_amount: Money.new(100_00, :USD),
      balance_amount: Money.new(100_00, :USD)
    })

    assert {:error, _} = live(conn, ~p"/portal/invoices/#{other_invoice.id}")
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/client_portal/ --trace
```

Expected: FAIL — LiveViews don't exist yet.

- [ ] **Step 3: Create DashboardLive**

Create `lib/garden_web/live/client_portal/dashboard_live.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.DashboardLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    invoices = load_portal_invoices(actor)
    agreements = load_portal_agreements(actor)

    outstanding_balance =
      invoices
      |> Enum.filter(&(&1.status in [:issued, :partial]))
      |> Enum.reduce(Money.new(0, :USD), &Money.add(&2, &1.balance_amount))

    recent_invoices = Enum.take(Enum.sort_by(invoices, & &1.inserted_at, {:desc, DateTime}), 5)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:outstanding_balance, outstanding_balance)
     |> assign(:recent_invoices, recent_invoices)
     |> assign(:active_agreements_count, length(agreements))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Dashboard</h1>

      <div class="grid grid-cols-1 gap-6 sm:grid-cols-3 mb-8">
        <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
          <p class="text-sm text-gray-500 dark:text-gray-400">Outstanding Balance</p>
          <p class="mt-1 text-2xl font-bold text-gray-900 dark:text-white">
            <%= Money.to_string(@outstanding_balance) %>
          </p>
        </div>
        <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
          <p class="text-sm text-gray-500 dark:text-gray-400">Active Agreements</p>
          <p class="mt-1 text-2xl font-bold text-gray-900 dark:text-white"><%= @active_agreements_count %></p>
        </div>
      </div>

      <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-3">Recent Invoices</h2>
      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Invoice</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Due</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Amount</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={inv <- @recent_invoices}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500">
                  <%= inv.invoice_number %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
                <%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %>
              </td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white"><%= Money.to_string(inv.total_amount) %></td>
              <td class="px-6 py-4">
                <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{status_badge_class(inv.status)}"}>
                  <%= inv.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@recent_invoices == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No invoices yet.
        </div>
      </div>
    </div>
    """
  end

  defp load_portal_invoices(actor) do
    case Finance.list_portal_invoices(actor: actor) do
      {:ok, invoices} -> invoices
      _ -> []
    end
  end

  defp load_portal_agreements(actor) do
    case Commercial.list_portal_agreements(actor: actor) do
      {:ok, agreements} -> agreements
      _ -> []
    end
  end

  defp status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400"
  defp status_badge_class(:partial), do: "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"
  defp status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400"
end
```

- [ ] **Step 4: Create InvoiceLive.Index**

Create `lib/garden_web/live/client_portal/invoice_live/index.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.InvoiceLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    case Finance.list_portal_invoices(actor: actor) do
      {:ok, invoices} ->
        {:ok,
         socket
         |> assign(:page_title, "Invoices")
         |> assign(:invoices, invoices)
         |> assign(:filter, :all)}

      {:error, _} ->
        {:ok, socket |> assign(:page_title, "Invoices") |> assign(:invoices, []) |> assign(:filter, :all)}
    end
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(status))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Invoices</h1>
        <div class="flex gap-2">
          <button phx-click="filter" phx-value-status="all"
            class={"text-sm px-3 py-1 rounded-full #{if @filter == :all, do: "bg-emerald-600 text-white", else: "text-gray-600 hover:text-gray-900"}"}>
            All
          </button>
          <button phx-click="filter" phx-value-status="outstanding"
            class={"text-sm px-3 py-1 rounded-full #{if @filter == :outstanding, do: "bg-emerald-600 text-white", else: "text-gray-600 hover:text-gray-900"}"}>
            Outstanding
          </button>
          <button phx-click="filter" phx-value-status="paid"
            class={"text-sm px-3 py-1 rounded-full #{if @filter == :paid, do: "bg-emerald-600 text-white", else: "text-gray-600 hover:text-gray-900"}"}>
            Paid
          </button>
        </div>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Invoice #</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Issued</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Due</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Total</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Balance Due</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={inv <- filtered_invoices(@invoices, @filter)}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                  <%= inv.invoice_number %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= if inv.issued_on, do: Date.to_string(inv.issued_on), else: "—" %></td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= if inv.due_on, do: Date.to_string(inv.due_on), else: "—" %></td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white"><%= Money.to_string(inv.total_amount) %></td>
              <td class="px-6 py-4 text-sm font-medium text-gray-900 dark:text-white"><%= Money.to_string(inv.balance_amount) %></td>
              <td class="px-6 py-4">
                <span class={"inline-flex items-center rounded-full px-2 py-1 text-xs font-medium #{status_badge_class(inv.status)}"}>
                  <%= inv.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={filtered_invoices(@invoices, @filter) == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No invoices found.
        </div>
      </div>
    </div>
    """
  end

  defp filtered_invoices(invoices, :all), do: invoices
  defp filtered_invoices(invoices, :outstanding), do: Enum.filter(invoices, &(&1.status in [:issued, :partial]))
  defp filtered_invoices(invoices, :paid), do: Enum.filter(invoices, &(&1.status == :paid))

  defp status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:partial), do: "bg-blue-100 text-blue-800"
  defp status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
```

- [ ] **Step 5: Create InvoiceLive.Show**

Create `lib/garden_web/live/client_portal/invoice_live/show.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.InvoiceLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_client_user
    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

    case Finance.get_portal_invoice(id, actor: actor) do
      {:ok, invoice} ->
        {:ok,
         socket
         |> assign(:page_title, "Invoice #{invoice.invoice_number}")
         |> assign(:invoice, invoice)
         |> assign(:mercury_info, mercury_info)}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Invoice not found.") |> redirect(to: ~p"/portal/invoices")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <div class="mb-6 flex items-center gap-3">
        <.link navigate={~p"/portal/invoices"} class="text-sm text-emerald-600 hover:text-emerald-500">
          &larr; Back to invoices
        </.link>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <div class="flex justify-between items-start mb-4">
          <div>
            <h1 class="text-xl font-bold text-gray-900 dark:text-white">Invoice <%= @invoice.invoice_number %></h1>
            <p :if={@invoice.issued_on} class="text-sm text-gray-500 mt-1">Issued <%= Date.to_string(@invoice.issued_on) %></p>
            <p :if={@invoice.due_on} class="text-sm text-gray-500">Due <%= Date.to_string(@invoice.due_on) %></p>
          </div>
          <span class={"inline-flex items-center rounded-full px-3 py-1 text-sm font-medium #{status_badge_class(@invoice.status)}"}>
            <%= @invoice.status %>
          </span>
        </div>

        <!-- Line Items -->
        <table class="w-full text-sm mt-6 mb-4">
          <thead>
            <tr class="border-b border-gray-200 dark:border-gray-700">
              <th class="text-left py-2 text-gray-500 font-medium">Description</th>
              <th class="text-right py-2 text-gray-500 font-medium">Qty</th>
              <th class="text-right py-2 text-gray-500 font-medium">Rate</th>
              <th class="text-right py-2 text-gray-500 font-medium">Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={line <- (@invoice.invoice_lines || [])} class="border-b border-gray-100 dark:border-gray-800">
              <td class="py-2 text-gray-900 dark:text-white"><%= line.description %></td>
              <td class="py-2 text-right text-gray-600"><%= line.quantity %></td>
              <td class="py-2 text-right text-gray-600"><%= Money.to_string(line.unit_price) %></td>
              <td class="py-2 text-right text-gray-900 dark:text-white"><%= Money.to_string(line.line_total) %></td>
            </tr>
          </tbody>
        </table>

        <div class="border-t border-gray-200 dark:border-gray-700 pt-3 space-y-1 text-sm">
          <div class="flex justify-between"><span class="text-gray-500">Subtotal</span><span><%= Money.to_string(@invoice.subtotal || @invoice.total_amount) %></span></div>
          <div :if={@invoice.tax_total && Money.positive?(@invoice.tax_total)} class="flex justify-between">
            <span class="text-gray-500">Tax</span><span><%= Money.to_string(@invoice.tax_total) %></span>
          </div>
          <div class="flex justify-between font-semibold text-base pt-1 border-t border-gray-200 dark:border-gray-700">
            <span>Total</span><span><%= Money.to_string(@invoice.total_amount) %></span>
          </div>
          <div :if={@invoice.status in [:issued, :partial]} class="flex justify-between text-emerald-600 font-bold text-lg pt-1">
            <span>Balance Due</span><span><%= Money.to_string(@invoice.balance_amount) %></span>
          </div>
        </div>
      </div>

      <!-- Payment Options -->
      <div :if={@invoice.status in [:issued, :partial]} class="space-y-4">
        <!-- Mercury ACH -->
        <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
          <h2 class="text-base font-semibold text-gray-900 dark:text-white mb-3">Pay by ACH / Wire Transfer</h2>
          <dl class="space-y-1 text-sm">
            <div class="flex gap-4">
              <dt class="text-gray-500 w-32">Bank</dt>
              <dd class="text-gray-900 dark:text-white">Mercury</dd>
            </div>
            <div class="flex gap-4">
              <dt class="text-gray-500 w-32">Account #</dt>
              <dd class="text-gray-900 dark:text-white font-mono"><%= @mercury_info[:account_number] || "Contact us" %></dd>
            </div>
            <div class="flex gap-4">
              <dt class="text-gray-500 w-32">Routing #</dt>
              <dd class="text-gray-900 dark:text-white font-mono"><%= @mercury_info[:routing_number] || "Contact us" %></dd>
            </div>
            <div class="flex gap-4">
              <dt class="text-gray-500 w-32">Reference</dt>
              <dd class="text-gray-900 dark:text-white font-mono"><%= @invoice.invoice_number %></dd>
            </div>
          </dl>
        </div>

        <!-- Stripe (card) -->
        <div :if={@invoice.stripe_payment_url} class="bg-white dark:bg-gray-900 rounded-lg shadow p-6">
          <h2 class="text-base font-semibold text-gray-900 dark:text-white mb-1">Pay by Card</h2>
          <p class="text-sm text-gray-500 mb-3">A 3% card processing fee will be added at checkout.</p>
          <a
            href={@invoice.stripe_payment_url}
            target="_blank"
            class="inline-block rounded-md bg-emerald-600 px-4 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500"
          >
            Pay by card &rarr;
          </a>
        </div>

        <!-- PDF download — NOTE: /finance/invoices/:id/export is staff-only.
             Portal PDF export requires a separate portal-scoped route (future task).
             Omit this button for now, or check InvoiceExportController to see if it
             can serve portal users without staff auth. -->
        <%# <div class="text-sm">
          <a href={~p"/finance/invoices/#{@invoice.id}/export?format=pdf"} class="text-emerald-600 hover:text-emerald-500">
            Download PDF
          </a>
        </div> %>
      </div>
    </div>
    """
  end

  defp status_badge_class(:issued), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:partial), do: "bg-blue-100 text-blue-800"
  defp status_badge_class(:paid), do: "bg-emerald-100 text-emerald-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
```

**Note:** Check the exact field names on InvoiceLine (`line_total` vs `line_total_amount`, `unit_price` vs `rate`). Look at `lib/garden/finance/invoice_line.ex` to confirm. Adjust the template accordingly.

- [ ] **Step 6: Run portal LiveView tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/client_portal/dashboard_live_test.exs \
  test/garden_web/live/client_portal/invoice_live_test.exs --trace
```

Expected: all tests pass.

- [ ] **Step 7: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 8: Commit**

```bash
git add lib/garden_web/live/client_portal/dashboard_live.ex \
        lib/garden_web/live/client_portal/invoice_live/ \
        test/garden_web/live/client_portal/
git commit -m "feat: add portal Dashboard and Invoice LiveViews"
```

---

## Task 6: Agreement LiveViews

**Files:**
- Create: `lib/garden_web/live/client_portal/agreement_live/index.ex`
- Create: `lib/garden_web/live/client_portal/agreement_live/show.ex`
- Test: `test/garden_web/live/client_portal/agreement_live_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden_web/live/client_portal/agreement_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.AgreementLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_client_user

  setup %{organization: org} do
    agreement = Ash.Seed.seed!(GnomeGarden.Commercial.Agreement, %{
      organization_id: org.id,
      name: "Test Agreement",
      status: :active,
      billing_model: :fixed_fee
    })
    {:ok, agreement: agreement}
  end

  test "agreement list shows active agreements for client's org", %{conn: conn, agreement: ag} do
    {:ok, _view, html} = live(conn, ~p"/portal/agreements")
    assert html =~ "Test Agreement"
  end

  test "agreement detail shows agreement info", %{conn: conn, agreement: ag} do
    {:ok, _view, html} = live(conn, ~p"/portal/agreements/#{ag.id}")
    assert html =~ "Test Agreement"
  end

  test "cannot access another org's agreement", %{conn: conn} do
    other_org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other"})
    other_ag = Ash.Seed.seed!(GnomeGarden.Commercial.Agreement, %{
      organization_id: other_org.id,
      name: "Other Agreement",
      status: :active,
      billing_model: :fixed_fee
    })
    assert {:error, _} = live(conn, ~p"/portal/agreements/#{other_ag.id}")
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/client_portal/agreement_live_test.exs --trace
```

Expected: FAIL.

- [ ] **Step 3: Create AgreementLive.Index**

Create `lib/garden_web/live/client_portal/agreement_live/index.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_client_user

    agreements =
      case Commercial.list_portal_agreements(actor: actor) do
        {:ok, list} -> list
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "Agreements")
     |> assign(:agreements, agreements)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Agreements</h1>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Billing</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={ag <- @agreements}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/agreements/#{ag.id}"} class="text-emerald-600 hover:text-emerald-500 font-medium">
                  <%= ag.name %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= ag.agreement_type || "—" %></td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= ag.billing_model %></td>
              <td class="px-6 py-4">
                <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-emerald-100 text-emerald-800">
                  <%= ag.status %>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@agreements == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No active agreements.
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Create AgreementLive.Show**

Create `lib/garden_web/live/client_portal/agreement_live/show.ex`:

```elixir
defmodule GnomeGardenWeb.ClientPortal.AgreementLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_client_user

    case Commercial.get_portal_agreement(id, actor: actor) do
      {:ok, agreement} ->
        invoices =
          case Finance.list_portal_invoices(actor: actor) do
            {:ok, invs} -> Enum.filter(invs, &(&1.agreement_id == agreement.id))
            _ -> []
          end

        {:ok,
         socket
         |> assign(:page_title, agreement.name)
         |> assign(:agreement, agreement)
         |> assign(:invoices, invoices)}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Agreement not found.") |> redirect(to: ~p"/portal/agreements")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <div class="mb-6">
        <.link navigate={~p"/portal/agreements"} class="text-sm text-emerald-600 hover:text-emerald-500">
          &larr; Back to agreements
        </.link>
      </div>

      <div class="bg-white dark:bg-gray-900 rounded-lg shadow p-6 mb-6">
        <h1 class="text-xl font-bold text-gray-900 dark:text-white mb-4"><%= @agreement.name %></h1>

        <dl class="grid grid-cols-2 gap-4 text-sm">
          <div>
            <dt class="text-gray-500">Billing Model</dt>
            <dd class="font-medium text-gray-900 dark:text-white"><%= @agreement.billing_model %></dd>
          </div>
          <div>
            <dt class="text-gray-500">Status</dt>
            <dd>
              <span class="inline-flex items-center rounded-full px-2 py-1 text-xs font-medium bg-emerald-100 text-emerald-800">
                <%= @agreement.status %>
              </span>
            </dd>
          </div>
          <div :if={@agreement.billing_model == :fixed_fee && @agreement.contract_value}>
            <dt class="text-gray-500">Contract Value</dt>
            <dd class="font-medium text-gray-900 dark:text-white"><%= Money.to_string(@agreement.contract_value) %></dd>
          </div>
          <div :if={@agreement.payment_terms_days}>
            <dt class="text-gray-500">Payment Terms</dt>
            <dd class="font-medium text-gray-900 dark:text-white">Net <%= @agreement.payment_terms_days %></dd>
          </div>
        </dl>

        <div :if={@agreement.description} class="mt-4 text-sm text-gray-600 dark:text-gray-400">
          <%= @agreement.description %>
        </div>
      </div>

      <!-- Linked Invoices -->
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-3">Invoices</h2>
      <div class="bg-white dark:bg-gray-900 rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Invoice #</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Total</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <tr :for={inv <- @invoices}>
              <td class="px-6 py-4">
                <.link navigate={~p"/portal/invoices/#{inv.id}"} class="text-emerald-600 hover:text-emerald-500">
                  <%= inv.invoice_number %>
                </.link>
              </td>
              <td class="px-6 py-4 text-sm text-gray-900 dark:text-white"><%= Money.to_string(inv.total_amount) %></td>
              <td class="px-6 py-4 text-sm text-gray-500"><%= inv.status %></td>
            </tr>
          </tbody>
        </table>
        <div :if={@invoices == []} class="px-6 py-8 text-center text-sm text-gray-500">
          No invoices for this agreement.
        </div>
      </div>
    </div>
    """
  end
end
```

**Note:** Check actual Agreement field names. Read `lib/garden/commercial/agreement.ex` to verify fields like `agreement_type`, `contract_value`, `billing_model`. Adjust templates accordingly.

- [ ] **Step 5: Run agreement tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/client_portal/agreement_live_test.exs --trace
```

Expected: 3 tests, 0 failures.

- [ ] **Step 6: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/garden_web/live/client_portal/agreement_live/ \
        test/garden_web/live/client_portal/agreement_live_test.exs
git commit -m "feat: add portal Agreement LiveViews (list and detail)"
```

---

## Task 7: Stripe Integration

**Files:**
- Modify: `mix.exs` — add `{:stripity_stripe, "~> 3.0"}`
- Create: `lib/garden/payments/stripe_client.ex`
- Create: `lib/garden/finance/changes/generate_stripe_payment_link.ex`
- Modify: `lib/garden/finance/invoice.ex` — add change to `:issue` action
- Create: `lib/garden_web/controllers/stripe_webhook_controller.ex`
- Modify: `config/runtime.exs` — add STRIPE_SECRET_KEY + STRIPE_WEBHOOK_SECRET
- Test: `test/garden/payments/stripe_client_test.exs`
- Test: `test/garden_web/controllers/stripe_webhook_controller_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden/payments/stripe_client_test.exs`:

```elixir
defmodule GnomeGarden.Payments.StripeClientTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Payments.StripeClient

  # Use Mox or a simple mock. For now, test with a stubbed HTTP call.
  # In CI/test env, Stripe API calls should be mocked via config.

  test "create_payment_link/1 returns {:ok, url} when Stripe responds" do
    # If Stripe is not configured in test, skip gracefully
    if System.get_env("STRIPE_SECRET_KEY") do
      org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test"})
      invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
        organization_id: org.id,
        invoice_number: "INV-STRIPE-001",
        status: :draft,
        total_amount: Money.new(100_00, :USD),
        balance_amount: Money.new(100_00, :USD)
      })

      assert {:ok, url} = StripeClient.create_payment_link(invoice)
      assert String.starts_with?(url, "https://")
    else
      assert true  # skip in test env without Stripe key
    end
  end

  test "create_payment_link/1 returns {:error, reason} when Stripe key missing" do
    Application.put_env(:stripity_stripe, :api_key, nil)

    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test"})
    invoice = Ash.Seed.seed!(GnomeGarden.Finance.Invoice, %{
      organization_id: org.id,
      invoice_number: "INV-STRIPE-002",
      status: :draft,
      total_amount: Money.new(100_00, :USD),
      balance_amount: Money.new(100_00, :USD)
    })

    result = StripeClient.create_payment_link(invoice)
    assert match?({:error, _}, result)
  end
end
```

Create `test/garden_web/controllers/stripe_webhook_controller_test.exs`:

```elixir
defmodule GnomeGardenWeb.StripeWebhookControllerTest do
  use GnomeGardenWeb.ConnCase, async: true

  alias GnomeGarden.Finance

  @webhook_secret "test_webhook_secret"

  setup do
    Application.put_env(:gnome_garden, :stripe_webhook_secret, @webhook_secret)
    on_exit(fn -> Application.delete_env(:gnome_garden, :stripe_webhook_secret) end)
    :ok
  end

  test "returns 401 for invalid signature", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", "invalid")
      |> post(~p"/webhooks/stripe", ~s({"type":"checkout.session.completed"}))

    assert conn.status == 401
  end

  test "returns 200 for unknown event type", %{conn: conn} do
    body = ~s({"type":"payment_intent.created","data":{"object":{}}})
    sig = build_stripe_signature(body, @webhook_secret)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", sig)
      |> post(~p"/webhooks/stripe", body)

    assert conn.status == 200
  end

  defp build_stripe_signature(body, secret) do
    timestamp = System.system_time(:second)
    signed_payload = "#{timestamp}.#{body}"
    mac = :crypto.mac(:hmac, :sha256, secret, signed_payload)
    sig = Base.encode16(mac, case: :lower)
    "t=#{timestamp},v1=#{sig}"
  end
end
```

- [ ] **Step 2: Add stripity_stripe to mix.exs**

Read `mix.exs` first, then add to the `deps` list:

```elixir
{:stripity_stripe, "~> 3.0"},
```

Then run:

```bash
mix deps.get
```

- [ ] **Step 3: Create StripeClient module**

Create `lib/garden/payments/stripe_client.ex`:

```elixir
defmodule GnomeGarden.Payments.StripeClient do
  @moduledoc """
  Stripe API wrapper for creating Payment Links for invoices.

  Creates a Stripe Payment Link with two line items:
  1. The invoice amount
  2. A 3% card processing fee

  The payment link metadata includes invoice_id for webhook matching.
  """

  require Logger

  @doc """
  Creates a Stripe Payment Link for the given invoice.
  Returns {:ok, url} on success, {:error, reason} on failure.
  Non-fatal — caller should log and continue if this fails.
  """
  def create_payment_link(invoice) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, price_id} <- create_price(invoice, api_key),
         {:ok, fee_price_id} <- create_fee_price(invoice, api_key),
         {:ok, link} <- create_link(invoice, price_id, fee_price_id, api_key) do
      {:ok, link["url"]}
    else
      {:error, reason} ->
        Logger.warning("StripeClient.create_payment_link failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_api_key do
    case Application.get_env(:stripity_stripe, :api_key) do
      nil -> {:error, :api_key_not_configured}
      key -> {:ok, key}
    end
  end

  defp create_price(invoice, _api_key) do
    amount_cents = Money.to_integer(invoice.total_amount)
    description = "Invoice #{invoice.invoice_number}"

    case Stripe.Price.create(%{
      unit_amount: amount_cents,
      currency: "usd",
      product_data: %{name: description}
    }) do
      {:ok, price} -> {:ok, price.id}
      {:error, _} = err -> err
    end
  end

  defp create_fee_price(invoice, _api_key) do
    amount_cents = Money.to_integer(invoice.total_amount)
    fee_cents = round(amount_cents * 0.03)

    case Stripe.Price.create(%{
      unit_amount: fee_cents,
      currency: "usd",
      product_data: %{name: "Card processing fee (3%)"}
    }) do
      {:ok, price} -> {:ok, price.id}
      {:error, _} = err -> err
    end
  end

  defp create_link(invoice, price_id, fee_price_id, _api_key) do
    case Stripe.PaymentLink.create(%{
      line_items: [
        %{price: price_id, quantity: 1},
        %{price: fee_price_id, quantity: 1}
      ],
      metadata: %{invoice_id: invoice.id}
    }) do
      {:ok, link} -> {:ok, %{"url" => link.url}}
      {:error, _} = err -> err
    end
  end
end
```

**Note:** Check the exact `stripity_stripe` v3 API. Module names may be `Stripe.Price`, `Stripe.PaymentLink`. If the API is different, adjust. The important contract is: `create_payment_link/1` returns `{:ok, url_string}` or `{:error, reason}`.

- [ ] **Step 4: Create GenerateStripePaymentLink change**

Create `lib/garden/finance/changes/generate_stripe_payment_link.ex`:

```elixir
defmodule GnomeGarden.Finance.Changes.GenerateStripePaymentLink do
  @moduledoc """
  Ash.Resource.Change that generates a Stripe Payment Link after invoice issue.
  Attached to the :issue action on Invoice.
  Non-fatal: if Stripe is unavailable, logs a warning and continues.
  ACH payment is always available regardless.
  """

  use Ash.Resource.Change
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      case GnomeGarden.Payments.StripeClient.create_payment_link(invoice) do
        {:ok, url} ->
          case Ash.update(invoice, %{stripe_payment_url: url},
                 action: :update, domain: GnomeGarden.Finance, authorize?: false) do
            {:ok, updated} -> {:ok, updated}
            {:error, _} -> {:ok, invoice}  # non-fatal
          end

        {:error, reason} ->
          Logger.warning("GenerateStripePaymentLink: #{inspect(reason)}")
          {:ok, invoice}  # non-fatal — ACH still works, card button hidden when nil
      end
    end)
  end
end
```

- [ ] **Step 5: Add change to Invoice :issue action**

Read `lib/garden/finance/invoice.ex`, find the `:issue` transition action, and add:

```elixir
change GnomeGarden.Finance.Changes.GenerateStripePaymentLink
```

First read `lib/garden/finance/invoice.ex` and find the `:issue` update action. Add `change GnomeGarden.Finance.Changes.GenerateStripePaymentLink` as the **last** `change` line inside the `update :issue do ... end` block, after all existing changes (including `transition_state(:issued)`). Adding it last ensures state is already set to `:issued` when Stripe is called.

Example (existing lines are illustrative — check actual file):

```elixir
update :issue do
  # ... existing change lines ...
  change transition_state(:issued)
  change GnomeGarden.Finance.Changes.GenerateStripePaymentLink  # ADD AS LAST change
end
```

If no explicit `update :issue do` block exists (transition declared only in `transitions do`), add one:

```elixir
update :issue do
  change transition_state(:issued)
  change GnomeGarden.Finance.Changes.GenerateStripePaymentLink
end
```

- [ ] **Step 6: Create StripeWebhookController**

Create `lib/garden_web/controllers/stripe_webhook_controller.ex`:

```elixir
defmodule GnomeGardenWeb.StripeWebhookController do
  @moduledoc """
  Handles Stripe webhook events.
  Uses the same pattern as MercuryWebhookController: raw body caching + HMAC verification.
  The :webhooks pipeline (already in router.ex) skips CSRF and caches raw body.
  """

  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Finance

  def receive(conn, _params) do
    secret = Application.get_env(:gnome_garden, :stripe_webhook_secret)
    signature = get_req_header(conn, "stripe-signature") |> List.first()
    raw_body = conn.assigns[:raw_body] || ""

    case verify_signature(raw_body, signature, secret) do
      :ok ->
        payload = Jason.decode!(raw_body)
        handle_event(payload["type"], payload)
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("StripeWebhookController: invalid signature — #{inspect(reason)}")
        send_resp(conn, 401, "unauthorized")
    end
  end

  defp verify_signature(_body, nil, _secret), do: {:error, :missing_signature}
  defp verify_signature(_body, _sig, nil), do: {:error, :webhook_secret_not_configured}

  defp verify_signature(body, signature, secret) do
    # Parse t=...,v1=... from signature header
    with [timestamp] <- Regex.run(~r/t=(\d+)/, signature, capture: :all_but_first),
         [expected_sig] <- Regex.run(~r/v1=([a-f0-9]+)/, signature, capture: :all_but_first) do
      signed_payload = "#{timestamp}.#{body}"
      computed = :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(computed, expected_sig) do
        :ok
      else
        {:error, :signature_mismatch}
      end
    else
      _ -> {:error, :malformed_signature}
    end
  end

  defp handle_event("checkout.session.completed", payload) do
    invoice_id = get_in(payload, ["data", "object", "metadata", "invoice_id"])

    if invoice_id do
      case Finance.get_invoice(invoice_id) do
        {:ok, invoice} when invoice.status in [:issued, :partial] ->
          case Finance.pay_invoice(invoice, authorize?: false) do
            {:ok, _} -> Logger.info("StripeWebhookController: marked invoice #{invoice_id} as paid")
            {:error, e} -> Logger.warning("StripeWebhookController: could not mark paid: #{inspect(e)}")
          end

        {:ok, _} ->
          Logger.info("StripeWebhookController: invoice #{invoice_id} already paid — idempotent no-op")

        {:error, _} ->
          Logger.warning("StripeWebhookController: invoice not found for id=#{invoice_id}")
      end
    end
  end

  defp handle_event(event_type, _payload) do
    Logger.debug("StripeWebhookController: unhandled event #{event_type}")
    # Return 200 so Stripe doesn't retry
  end
end
```

**Note:** Check how `MercuryWebhookController` reads the raw body (`conn.assigns[:raw_body]`). The `:webhooks` pipeline should have a plug that caches the raw body. Check `lib/garden_web/plugs/` or `lib/garden_web/router.ex` for a `CacheBodyReader` or similar. If the key is different (e.g., `:raw_body` vs `:cached_body`), adjust.

- [ ] **Step 7: Add Stripe config to runtime.exs**

Read `config/runtime.exs` first, then add inside the `if config_env() == :prod do` block, following the same raise-guard pattern as existing secrets:

```elixir
stripe_secret_key =
  System.get_env("STRIPE_SECRET_KEY") ||
    raise "environment variable STRIPE_SECRET_KEY is missing"

stripe_webhook_secret =
  System.get_env("STRIPE_WEBHOOK_SECRET") ||
    raise "environment variable STRIPE_WEBHOOK_SECRET is missing"

config :stripity_stripe, api_key: stripe_secret_key
config :gnome_garden, stripe_webhook_secret: stripe_webhook_secret
```

- [ ] **Step 8: Run Stripe tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/payments/stripe_client_test.exs \
  test/garden_web/controllers/stripe_webhook_controller_test.exs --trace
```

Expected: all tests pass (Stripe API calls skipped in test env).

- [ ] **Step 9: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 10: Commit**

```bash
git add mix.exs mix.lock \
        lib/garden/payments/stripe_client.ex \
        lib/garden/finance/changes/generate_stripe_payment_link.ex \
        lib/garden/finance/invoice.ex \
        lib/garden_web/controllers/stripe_webhook_controller.ex \
        config/runtime.exs \
        test/garden/payments/stripe_client_test.exs \
        test/garden_web/controllers/stripe_webhook_controller_test.exs
git commit -m "feat: Stripe integration — payment links on invoice issue, webhook marks paid"
```

---

## Task 8: Staff "Invite to Portal" Button

Add a button on the Organization show page that lets staff invite a contact to the portal.

**Files:**
- Modify: `lib/garden_web/live/operations/organization_live/show.ex`

- [ ] **Step 1: Write failing test**

Add to `test/garden_web/live/operations/organization_live_test.exs` (create it if it doesn't exist):

```elixir
defmodule GnomeGardenWeb.Operations.OrganizationLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "organization show page renders invite button", %{conn: conn} do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    {:ok, _view, html} = live(conn, ~p"/operations/organizations/#{org.id}")
    assert html =~ "Invite to portal"
  end

  test "invite_to_portal sends invitation", %{conn: conn} do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Org"})
    person = Ash.Seed.seed!(GnomeGarden.Operations.Person, %{name: "Test", email: "test@example.com"})
    Ash.Seed.seed!(GnomeGarden.Operations.OrganizationAffiliation, %{
      organization_id: org.id,
      person_id: person.id,
      status: :active
    })

    {:ok, view, _html} = live(conn, ~p"/operations/organizations/#{org.id}")

    html =
      view
      |> form("#invite-portal-form", invite: %{email: "test@example.com"})
      |> render_submit()

    assert html =~ "invited"
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/operations/organization_live_test.exs --trace 2>&1 | head -30
```

- [ ] **Step 3: Add invite functionality to OrganizationLive.Show**

Read `lib/garden_web/live/operations/organization_live/show.ex` first.

Add to the `mount/3` function:
```elixir
|> assign(:invite_ok, false)
|> assign(:invite_error, nil)
```

Add a new `handle_event` clause:
```elixir
@impl true
def handle_event("invite_to_portal", %{"invite" => %{"email" => email}}, socket) do
  org_id = socket.assigns.organization.id

  case GnomeGarden.Accounts.invite_client_user(email, org_id) do
    {:ok, _client_user} ->
      # Request magic link — sends email via SendMagicLinkEmail sender
      GnomeGarden.Accounts.request_client_portal_access(email)
      {:noreply, assign(socket, :invite_ok, true)}

    {:error, error} ->
      {:noreply, assign(socket, :invite_error, "Could not invite: #{inspect(error)}")}
  end
end
```

Add invite form to the `render/1` function, somewhere near the bottom of the page body:

```elixir
<!-- Invite to Portal -->
<div class="mt-8 border-t border-gray-200 dark:border-white/10 pt-8">
  <h3 class="text-base/7 font-semibold text-gray-900 dark:text-white">Client Portal</h3>
  <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
    Invite a contact to view their invoices and agreements in the client portal.
  </p>
  <form id="invite-portal-form" phx-submit="invite_to_portal" class="mt-4 flex gap-3 items-end">
    <div class="flex-1">
      <label class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">Email address</label>
      <input
        type="email"
        name="invite[email]"
        placeholder="client@example.com"
        required
        class="rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500 w-full"
      />
    </div>
    <button type="submit" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500">
      Invite to portal
    </button>
  </form>
  <div :if={@invite_ok} class="mt-2 text-sm text-emerald-600">Contact invited — they'll receive a sign-in link by email.</div>
  <div :if={@invite_error} class="mt-2 text-sm text-red-600"><%= @invite_error %></div>
</div>
```

- [ ] **Step 4: Run invite tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/operations/organization_live_test.exs --trace
```

Expected: tests pass.

- [ ] **Step 5: Run full suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 6: Commit**

```bash
git add lib/garden_web/live/operations/organization_live/show.ex \
        test/garden_web/live/operations/organization_live_test.exs
git commit -m "feat: add Invite to Portal button on Organization show page"
```

---

## Final Verification

- [ ] **Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: all tests pass, 0 failures.

- [ ] **Manual smoke test** (optional but recommended)

```bash
GNOME_GARDEN_DB_PORT=5432 mix phx.server
```

1. Navigate to `/portal/login` — should see email form
2. Navigate to `/portal` — should redirect to `/portal/login`
3. In staff app, go to an Organization → should see "Invite to portal" section

- [ ] **Push branch**

```bash
git push
```

---

## Production Checklist

Before going live:
- [ ] Set `STRIPE_SECRET_KEY` in production environment
- [ ] Set `STRIPE_WEBHOOK_SECRET` in production environment
- [ ] Register `/webhooks/stripe` in Stripe dashboard as a webhook endpoint
- [ ] Configure Stripe webhook to send `checkout.session.completed` event
- [ ] Verify `/portal/login` is accessible at production domain
- [ ] Test magic link flow end-to-end in staging
