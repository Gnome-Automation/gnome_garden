# GnomeGarden Agent Guidelines

This is a Phoenix + Ash + Jido application. Follow these guidelines strictly.

## Critical: Documentation Lookup

**Always search docs before implementing.** Use these mix tasks:

```bash
# Get docs for a module or function
mix usage_rules.docs Ash.Resource
mix usage_rules.docs Ash.Changeset.for_create/4

# Search across all package docs
mix usage_rules.search_docs "code interface"
mix usage_rules.search_docs "belongs_to" -p ash
```

Also run `mix help <task>` before using generators, codegen, migration, or
project-specific Mix tasks whose options matter.

## Critical: Codex Architecture Map

For implemented architecture and data-model lookup, treat these as authoritative:

- `docs/llm/index.md`
- `docs/llm/generated/resources.json`
- `config/config.exs` under `config :gnome_garden, :ash_domains`

Refresh the machine map after changing any Ash domain or resource:

```bash
mix llm.generate_resource_map
```

The files under `documentation/architecture/` and `documentation/domains/` may include planned or aspirational model details. Do not treat them as implemented unless the same domain or resource also appears in `docs/llm/generated/resources.json`.

## Ash Framework Guidelines

### Ash Design Order

Ash is the application boundary for persisted business behavior. When deciding
where logic belongs, use this order:

1. Existing domain code interface.
2. Existing resource action, policy, preparation, validation, change,
   calculation, aggregate, relationship, identity, or action hook.
3. A new intent-named Ash action exposed through the domain.
4. A domain-local Ash extension module under `changes/`, `preparations/`,
   `calculations/`, `validations/`, or `aggregates/`.
5. Plain Elixir service code only for external orchestration, transport,
   protocol parsing, LLM/tool coordination, or runtime process concerns.

Keep domain facades thin. They should expose and compose Ash actions, not grow
into parallel context layers. Treat helper-heavy resources, repeated domain
helpers, or Ash logic in web modules as design pressure to add or refine
resource actions.

Do not put frontend-specific query builders in backend domain modules. For
tables and Cinder collections, prefer passing `resource={...}` and
`action={...}` so Cinder calls Ash read actions directly. If a table needs a
special backend shape, model it as an Ash read action/preparation with clear
arguments instead of adding `def some_table_query/0` helpers to a domain.
Keep unavoidable UI query glue at the LiveView/component edge until it can be
expressed as a real Ash action.

Do not expose low-level state-machine transition actions as domain code
interfaces when a higher-level workflow module owns the business process. For
example, acquisition finding review transitions stay behind
`GnomeGarden.Acquisition.Review` and its public workflow functions instead of
raw `accept_finding` / `reject_finding` interfaces.

When cleanup reveals a durable architectural rule or correction, add it to this
file in the same pass so future agents do not have to rediscover it from chat.

### Resource Structure

Resources are the core abstraction. Always structure them as:

```elixir
defmodule GnomeGarden.MyDomain.MyResource do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.MyDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: []  # Add extensions here: AshStateMachine, AshOban, etc.

  postgres do
    table "my_resources"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    # Custom actions go here
  end

  policies do
    # Define authorization policies
  end

  attributes do
    uuid_primary_key :id
    # Define attributes
  end

  relationships do
    # Define relationships
  end

  identities do
    # Define unique constraints
  end
end
```

### Domain Structure with Code Interfaces

Domains group resources and expose code interfaces. **Always define code interfaces for external use:**

```elixir
defmodule GnomeGarden.MyDomain do
  use Ash.Domain, otp_app: :gnome_garden, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.MyDomain.MyResource do
      # Code interfaces - the idiomatic way to call actions
      define :list_resources, action: :read
      define :get_resource, action: :read, get_by: :id
      define :get_resource_by_slug, action: :read, get_by: :slug
      define :create_resource, action: :create
      define :update_resource, action: :update
      define :delete_resource, action: :destroy
    end
  end
end
```

### Calling Actions - The Idiomatic Way

**NEVER use raw Ecto. NEVER use Repo directly for Ash resources.**

```elixir
# WRONG - Don't do this
GnomeGarden.Repo.all(MyResource)
GnomeGarden.Repo.insert(%MyResource{name: "foo"})

# CORRECT - Use code interfaces (preferred)
GnomeGarden.MyDomain.list_resources()
GnomeGarden.MyDomain.create_resource(%{name: "foo"})
GnomeGarden.MyDomain.get_resource(id)

# OK inside domain/resource internals or narrow setup paths when no interface exists
Ash.read!(MyResource)
Ash.create!(MyResource, %{name: "foo"})

# With actor (current user) for authorization
GnomeGarden.MyDomain.list_resources(actor: current_user)
Ash.read!(MyResource, actor: current_user)
```

### Action Patterns

```elixir
actions do
  # Default CRUD - use :* to accept all public attributes
  defaults [:read, :destroy, create: :*, update: :*]

  # Custom read with arguments
  read :search do
    argument :query, :string, allow_nil?: false
    filter expr(contains(name, ^arg(:query)))
  end

  # Read that returns single record
  read :get_by_email do
    get_by :email  # Returns {:ok, record} or {:error, :not_found}
  end

  # Create with custom logic
  create :register do
    accept [:email, :name]

    change set_attribute(:status, :pending)
    change {MyApp.Changes.SendWelcomeEmail, []}
  end

  # Update with state machine transition
  update :publish do
    require_atomic? false  # Required for complex changes
    change transition_state(:published)
  end

  # Generic action (not tied to CRUD)
  action :send_notification, :boolean do
    argument :message, :string, allow_nil?: false
    run fn input, _context ->
      # Custom logic here
      {:ok, true}
    end
  end
end
```

### Relationships

```elixir
relationships do
  belongs_to :user, GnomeGarden.Accounts.User do
    allow_nil? false
  end

  has_many :comments, GnomeGarden.Content.Comment do
    destination_attribute :post_id
  end

  many_to_many :tags, GnomeGarden.Content.Tag do
    through GnomeGarden.Content.PostTag
    source_attribute_on_join_resource :post_id
    destination_attribute_on_join_resource :tag_id
  end
end
```

### AshStorage and Shared Documents

When using `ash_storage`, remember that the extension itself only gives you
one host resource to one file or one host resource to many files. If the same
file needs to apply to multiple parent records, or the parent-to-file link has
its own metadata, model that explicitly in Ash instead of trying to force it
into the attachment primitive.

- Use a dedicated document/file resource for the reusable file metadata.
- Put `ash_storage` on the resource that actually owns the blob/attachment
  behavior.
- If parent-specific metadata exists, add a join resource for the relationship
  (for example `FindingDocument`, `ParentRecordDocument`, etc.).
- Keep relationship-specific fields like `is_primary`, `effective_on`, `notes`,
  `document_role`, or `required_for_promotion` on the join resource, not on the
  blob itself.
- If you need convenience access from parent to shared document, use Ash
  `through` relationships instead of duplicating file state.

Use the right `through` feature for the job:

- `many_to_many ... through: JoinResource` is the writable pattern for a real
  many-to-many relationship with join metadata.
- `has_many` / `has_one ... through: [:join_relationship, :destination]` is a
  read-only shortcut path for loading/filtering the final related records.
- Do not confuse these two `through` features. They solve different problems.

Practical `ash_storage` guidance:

- Standard setup is:
  - one blob resource
  - one attachment resource
  - one or more host resources with `has_one_attached` / `has_many_attached`
- For shared attachments across multiple resource types, the attachment
  resource can declare multiple `belongs_to_resource` entries.
- For fully polymorphic attachments, omit `belongs_to_resource` and use the
  generic attachment pattern.
- Prefer direct uploads for large files using
  `AshStorage.Operations.prepare_direct_upload/3` plus
  `AshStorage.Changes.AttachBlob`.
- For simpler create/update flows, use `AshStorage.Changes.HandleFileArgument`
  with `Ash.Type.File`.
- In tests, switch the resource service to `AshStorage.Service.Test` and reset
  it between tests.

### Calculations and Aggregates

```elixir
calculations do
  calculate :full_name, :string, expr(first_name <> " " <> last_name)

  calculate :display_name, :string do
    calculation fn records, _context ->
      Enum.map(records, fn record ->
        record.nickname || record.full_name
      end)
    end
  end
end

aggregates do
  count :comment_count, :comments
  sum :total_amount, :line_items, :amount
  first :latest_comment, :comments, :body do
    sort inserted_at: :desc
  end
end
```

When a resource needs presentation-facing derived values, prefer Ash calculations over
LiveView/helper mapping functions. For example, if a record has a lifecycle field like
`status`, `stage`, or `priority`, and the UI needs a stable badge variant such as
`:default`, `:info`, `:warning`, `:success`, or `:error`, model that as a calculation on
the resource (for example `calculate :status_variant, :atom, expr(...)`) and load it from
the domain. Do not scatter one-off helper functions across the web layer for status-to-badge
or stage-to-color mappings when that mapping is part of the resource's meaning.

### Leverage Ash - Don't Write Custom Functions

**Use Ash's declarative DSL instead of writing Elixir functions.** Ash provides:

#### Changes (for create/update logic)
```elixir
# WRONG - Don't write a function
def set_published_at(record) do
  Map.put(record, :published_at, DateTime.utc_now())
end

# CORRECT - Use built-in changes
create :publish do
  change set_attribute(:published_at, &DateTime.utc_now/0)
  change set_attribute(:status, :published)
  change relate_actor(:published_by)  # Set relationship to current user
  change {MyApp.Changes.NotifySubscribers, []}  # Custom change module when needed
end
```

#### Preparations (for read query logic)
```elixir
# WRONG - Don't filter in your LiveView
def mount(_, _, socket) do
  posts = MyDomain.list_posts() |> Enum.filter(& &1.published)
  ...
end

# CORRECT - Use preparations in the resource
read :published do
  filter expr(status == :published)
  prepare build(sort: [inserted_at: :desc])
  prepare build(load: [:author, :comment_count])
end

# Then just call:
MyDomain.list_published_posts()
```

#### Calculations (for derived values)
```elixir
# WRONG - Don't compute in templates or LiveViews
def full_name(user), do: "#{user.first_name} #{user.last_name}"

# CORRECT - Define as calculation
calculations do
  calculate :full_name, :string, expr(first_name <> " " <> last_name)

  calculate :initials, :string, expr(
    fragment("substring(? from 1 for 1) || substring(? from 1 for 1)",
             first_name, last_name)
  )

  # Complex calculation with module
  calculate :avatar_url, :string, {MyApp.Calculations.AvatarUrl, []}
end
```

#### Aggregates (for counts, sums, etc.)
```elixir
# WRONG - Don't count in code
def comment_count(post) do
  length(post.comments)
end

# CORRECT - Define as aggregate
aggregates do
  count :comment_count, :comments
  count :published_comment_count, :comments do
    filter expr(status == :published)
  end
  sum :total_revenue, :orders, :amount
  first :latest_comment_body, :comments, :body do
    sort inserted_at: :desc
  end
  list :tag_names, :tags, :name
end
```

#### Validations (for data integrity)
```elixir
# WRONG - Don't validate in controller/LiveView
def create_post(params) do
  if String.length(params.title) < 3 do
    {:error, "Title too short"}
  else
    ...
  end
end

# CORRECT - Use validations in resource
validations do
  validate string_length(:title, min: 3, max: 200)
  validate match(:email, ~r/@/)
  validate present(:body, message: "Post body is required")
  validate {MyApp.Validations.NoProfanity, attribute: :body}

  # Conditional validation
  validate present(:published_at) do
    where [status: :published]
  end
end
```

#### Built-in Changes Reference
```elixir
# Common built-in changes
change set_attribute(:field, value)
change set_attribute(:field, &DateTime.utc_now/0)  # With function
change relate_actor(:user)                          # Set relationship to actor
change manage_relationship(:tags, type: :append)   # Manage relationships
change increment(:view_count)                       # Atomic increment
change set_new_attribute(:field, value)            # Only if not already set
change filter expr(author_id == ^actor(:id))       # Filter for authorization
change after_action(fn changeset, record, _context -> ... end)
```

#### Built-in Preparations Reference
```elixir
# Common built-in preparations
prepare build(sort: [inserted_at: :desc])
prepare build(load: [:author, :comments])
prepare build(limit: 10)
prepare filter expr(status == :active)
prepare filter expr(user_id == ^actor(:id))  # Scope to current user
```

### Common Ash Mistakes to Avoid

1. **Don't write functions when Ash has a DSL feature** - Use changes, preps, calcs, aggs, validations
2. **Don't use Ecto changesets** - Use Ash actions and changes
3. **Don't query with Repo** - Use code interfaces or `Ash.read!/2`
4. **Don't forget the actor** - Pass `actor: user` for authorization
5. **Don't use `require_atomic? false` without reason** - Only for complex changes
6. **Don't compute derived values in LiveViews** - Use calculations
7. **Don't filter/sort in Elixir** - Use preparations and action arguments
8. **Don't count relationships in code** - Use aggregates
9. **Don't define relationships without foreign keys in postgres block**:
   ```elixir
   postgres do
     references do
       reference :user, on_delete: :delete
     end
   end
   ```
10. **Don't build Ash queries in callers when the shape has meaning** - If a
    LiveView, controller, worker, Jido action, or service needs filtering,
    sorting, loading, authorization checks, or a single-record lookup, model
    that as an intent-named read/action and expose it through the domain.

### AshPhoenix Forms in LiveViews

**Use `AshPhoenix.Form` for forms, not `to_form` with changesets:**

```elixir
defmodule GnomeGardenWeb.PostLive.New do
  use GnomeGardenWeb, :live_view

  def mount(_params, _session, socket) do
    form =
      GnomeGarden.Content.Post
      |> AshPhoenix.Form.for_create(:create,
        actor: socket.assigns.current_user,
        forms: [auto?: true]  # Auto-generate nested forms for relationships
      )
      |> to_form()

    {:ok, assign(socket, form: form)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created!")
         |> push_navigate(to: ~p"/posts/#{post.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end
end
```

**For updates:**
```elixir
def mount(%{"id" => id}, _session, socket) do
  post = GnomeGarden.Content.get_post!(id, actor: socket.assigns.current_user)

  form =
    post
    |> AshPhoenix.Form.for_update(:update,
      actor: socket.assigns.current_user,
      forms: [auto?: true]
    )
    |> to_form()

  {:ok, assign(socket, form: form, post: post)}
end
```

### Policies (Authorization)

```elixir
policies do
  # Bypass for admins
  bypass actor_attribute_equals(:role, :admin) do
    authorize_if always()
  end

  # Default deny
  policy always() do
    forbid_if always()
  end

  # Allow users to read published posts
  policy action_type(:read) do
    authorize_if expr(status == :published)
    authorize_if relates_to_actor_via(:author)  # Or own drafts
  end

  # Only author can update
  policy action_type([:update, :destroy]) do
    authorize_if relates_to_actor_via(:author)
  end
end
```

### AshStateMachine

```elixir
use Ash.Resource,
  extensions: [AshStateMachine]

state_machine do
  initial_states [:draft]
  default_initial_state :draft

  transitions do
    transition :submit, from: :draft, to: :pending_review
    transition :approve, from: :pending_review, to: :published
    transition :reject, from: :pending_review, to: :draft
    transition :archive, from: [:draft, :published], to: :archived
  end
end

attributes do
  attribute :status, :atom do
    constraints one_of: [:draft, :pending_review, :published, :archived]
    default :draft
    allow_nil? false
  end
end

actions do
  update :submit do
    change transition_state(:pending_review)
  end

  update :approve do
    change transition_state(:published)
    change set_attribute(:published_at, &DateTime.utc_now/0)
  end
end
```

### AshOban (Background Jobs)

```elixir
use Ash.Resource,
  extensions: [AshOban]

oban do
  triggers do
    trigger :send_welcome_email do
      action :send_welcome_email
      where expr(is_nil(welcome_email_sent_at))
      worker_read_action :read
    end
  end

  scheduled_actions do
    schedule :daily_digest, "0 9 * * *" do  # 9am daily
      action :send_daily_digest
    end
  end
end

actions do
  action :send_welcome_email, :boolean do
    run fn input, context ->
      # Send email logic
      {:ok, true}
    end
  end
end
```

### Loading Relationships & Calculations

```elixir
# Load in code interface call
GnomeGarden.Content.get_post!(id, load: [:author, :comments, :comment_count])

# Load after the fact
post = GnomeGarden.Content.get_post!(id)
post = Ash.load!(post, [:author, :comment_count])

# Nested loading
Ash.load!(post, [comments: [:author]])

# In action preparation (always loads)
read :with_details do
  prepare build(load: [:author, :comment_count, comments: [:author]])
end
```

### Error Handling

```elixir
# Use bang (!) when you expect success
post = GnomeGarden.Content.get_post!(id)  # Raises on not found

# Use ok tuple when handling errors
case GnomeGarden.Content.create_post(params, actor: user) do
  {:ok, post} -> ...
  {:error, %Ash.Error.Invalid{} = error} ->
    # Validation errors
    errors = Ash.Error.to_error_class(error)
    ...
  {:error, %Ash.Error.Forbidden{}} ->
    # Authorization failed
    ...
end

# In LiveView with AshPhoenix.Form - errors auto-populate
case AshPhoenix.Form.submit(form, params: params) do
  {:ok, record} -> ...
  {:error, form_with_errors} ->
    {:noreply, assign(socket, form: to_form(form_with_errors))}
end
```

### Testing Ash Resources

```elixir
defmodule GnomeGarden.Content.PostTest do
  use GnomeGarden.DataCase

  describe "create" do
    test "creates with valid attrs" do
      user = user_fixture()

      assert {:ok, post} =
        GnomeGarden.Content.create_post(
          %{title: "Test", body: "Content"},
          actor: user
        )

      assert post.title == "Test"
      assert post.author_id == user.id
    end

    test "fails without required fields" do
      user = user_fixture()

      assert {:error, %Ash.Error.Invalid{}} =
        GnomeGarden.Content.create_post(%{}, actor: user)
    end

    test "forbids without actor" do
      assert {:error, %Ash.Error.Forbidden{}} =
        GnomeGarden.Content.create_post(%{title: "Test"})
    end
  end
end
```

## Database & Migrations

### Creating/Modifying Resources

**CRITICAL: Use Ash migration workflow, NOT Ecto migrations:**

```bash
# 1. After changing resource attributes/relationships, generate migrations:
mix ash.codegen  # Prompts for migration name

# 2. Apply migrations:
mix ash.migrate

# NEVER use these for Ash resources:
# mix ecto.gen.migration  <- WRONG
# mix ecto.migrate        <- WRONG
```

### Other Ash Mix Tasks

```bash
# Generate a new resource
mix ash.gen.resource MyDomain.MyResource \
  --domain GnomeGarden.MyDomain \
  --attribute name:string \
  --relationship belongs_to:user:GnomeGarden.Accounts.User

# Generate a new domain
mix ash.gen.domain MyDomain

# Add extensions to existing resource
mix ash.extend GnomeGarden.MyDomain.MyResource AshStateMachine

# Reset database (drop, create, migrate)
mix ash.reset

# Rollback last migration
mix ash.rollback
```

## Jido Agent Framework

Jido is used for autonomous agents with pure functional design. Agents are immutable data structures.

### Defining an Agent

```elixir
defmodule GnomeGarden.Agents.TaskAgent do
  use Jido.Agent,
    name: "task_agent",
    description: "Manages task workflows",
    schema: [
      status: [type: :atom, default: :pending],
      result: [type: :any, default: nil]
    ],
    signal_routes: [
      {"process", GnomeGarden.Actions.ProcessTask},
      {"complete", GnomeGarden.Actions.CompleteTask}
    ]
end
```

### Defining Actions

```elixir
defmodule GnomeGarden.Actions.ProcessTask do
  use Jido.Action,
    name: "process_task",
    description: "Processes a task",
    schema: [
      task_id: [type: :string, required: true]
    ]

  def run(params, context) do
    # Pure function - return new state
    {:ok, %{status: :processing, task_id: params.task_id}}
  end
end
```

### Using Agents

```elixir
# Create agent (pure data)
agent = GnomeGarden.Agents.TaskAgent.new()

# Execute action (pure transformation)
{agent, directives} = GnomeGarden.Agents.TaskAgent.cmd(agent, {ProcessTask, %{task_id: "123"}})

# Deploy to runtime (OTP process)
{:ok, pid} = GnomeGarden.Jido.start_agent(TaskAgent, id: "task-1")

# Send signals
{:ok, agent} = Jido.AgentServer.call(pid, Jido.Signal.new!("process", %{task_id: "123"}))
```

### Jido Best Practices

1. **Agents are pure data** - No side effects in `cmd/2`
2. **Actions return state changes** - Not the side effects themselves
3. **Directives describe effects** - Emit, Spawn, Schedule, Stop
4. **Test without processes** - Agent logic is deterministic
5. **Check the wider Jido ecosystem before inventing custom orchestration** - Prefer existing Jido patterns, packages, and runtime primitives when the problem is agent/runtime orchestration
6. **Keep durable business rules in Ash unless the problem is truly agent orchestration** - Use Jido for coordination and runtime behavior, not as a replacement for core data/domain modeling

## Phoenix & LiveView Guidelines

### Phoenix v1.8

- **Always** wrap LiveView templates with `<Layouts.app flash={@flash} ...>`
- `core_components.ex` imports `<.icon name="hero-x-mark"/>` - use it
- Use `<.input>` component for forms, not raw HTML inputs
- **Never** use `<.flash_group>` outside `layouts.ex`

### LiveView Patterns

```elixir
defmodule GnomeGardenWeb.ResourceLive do
  use GnomeGardenWeb, :live_view

  # For authenticated routes:
  on_mount {GnomeGardenWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    {:ok, stream(socket, :resources, list_resources())}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    resource = get_resource!(id)
    {:ok, _} = delete_resource(resource, actor: socket.assigns.current_user)
    {:noreply, stream_delete(socket, :resources, resource)}
  end
end
```

### Streams - Always Use for Collections

```heex
<div id="resources" phx-update="stream">
  <div :for={{id, resource} <- @streams.resources} id={id}>
    {resource.name}
  </div>
</div>
```

Every direct child inside a `phx-update="stream"` container must have an `id`,
including empty-state placeholders. LiveView tests enforce this and will fail
with `setting phx-update to "stream" requires setting an ID on each child` if an
empty row or placeholder is missing one.

### Authentication Routes

Routes are pre-configured at:
- `/auth/*` - Authentication endpoints
- `/sign-in` - Sign in page
- `/register` - Registration
- `/sign-out` - Sign out

Use `on_mount {GnomeGardenWeb.LiveUserAuth, :live_user_required}` for protected LiveViews.

## Tailwind CSS v4

```css
/* app.css uses new import syntax */
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/gnome_garden_web";
```

- **No** `tailwind.config.js` needed
- **Never** use `@apply`
- Write custom Tailwind classes, avoid daisyUI (design your own)

## UI Consistency Guidelines

Build for all screen sizes by default. Do not treat desktop as the primary layout and
"let mobile collapse later." Every shared component, page shell, form, table, card, and
action row should be intentionally designed for:

- mobile first
- tablet
- desktop
- dark and light themes

### Design System Approach

- Prefer the repo's shared UI components first:
  - `GnomeGardenWeb.Components.WorkspaceUI`
  - `GnomeGardenWeb.Components.Protocol`
  - `GnomeGardenWeb.CoreComponents`
- If a pattern appears more than twice, extract or extend a shared component instead of
  rebuilding it ad hoc in LiveViews.
- Keep the app feeling like one operator system. Do not introduce page-specific visual
  styles that break the shared shell, spacing rhythm, or card language.
- Prefer Tailwind utilities as the default implementation tool. Use daisyUI classes only
  for lightweight primitives where they clearly reduce noise, such as dropdowns or simple
  button shells in the global navbar. Do not let daisyUI become a second design system.

### Responsive Layout Rules

- Start with the smallest screen first, then scale up with `sm:`, `md:`, `lg:`, and `xl:`.
- Avoid desktop-only rows that merely wrap on mobile. If content becomes cramped, switch
  layout direction on smaller screens with explicit `flex-col` or stacked blocks.
- Shared cards and action blocks should usually use:
  - compact spacing on mobile
  - larger spacing on desktop
  - smaller icons and type on mobile
  - larger visual treatments only from `sm:` upward
- Do not assume long labels, breadcrumbs, tab sets, or filter bars fit in one row on
  mobile. Make them scroll horizontally, stack, or simplify.
- For app-shell navigation:
  - desktop may use sidebar plus top shell
  - mobile must have a deliberate navigation model, not just a squeezed desktop nav
  - top-level nav controls must remain tappable and uncluttered on narrow screens

### Theme and Visual Consistency

- Every new UI must be legible in both light and dark mode.
- When adding surfaces, borders, badges, or muted text, provide both light and dark
  variants in the same component instead of leaving one mode visually unfinished.
- Reuse the existing color logic already present in shared components before adding new
  one-off color combinations.
- Keep status, intent, and severity colors consistent across screens. Do not remap the
  same meaning to different colors in different pages.

### Headers and Page Shell

- The global app navbar should contain shell-level controls only:
  - navigation access
  - section navigation / context when appropriate
  - theme toggle
  - profile/avatar menu
- The page title belongs in the page header, not duplicated in the global navbar.
- Prefer `WorkspaceUI.page_header/1` for major screen headers so the app keeps one header
  language across list, detail, and form views.
- Detail-page breadcrumb/back context should be consistent across sections and should come
  from shared shell or shared page components, not one-off inline links on every page.

### Forms

- Use one consistent form rhythm:
  - page header
  - one or more `form_section` or `section` blocks
  - actions at the bottom of the form
- Keep labels, help text, validation messages, and field spacing consistent.
- On mobile:
  - fields should stack vertically
  - multi-column forms should collapse to one column unless there is a strong reason not to
  - submit/cancel controls should remain easy to tap without horizontal crowding
- Avoid placing destructive or primary form actions in scattered locations. The main form
  action area should be obvious and predictable.

### CRUD Button Placement

- Use consistent action placement across create, edit, show, and index screens.
- For index/list pages:
  - primary create action goes in the page header actions area
  - filters/secondary actions stay in section headers or local toolbars
- For show/detail pages:
  - primary record actions live in the page header or the first prominent action row
  - destructive actions should be visually secondary and separated from the primary action
- For create/edit forms:
  - `Cancel` on the left or earlier in the action group
  - primary `Save` / `Create` / `Update` on the right or last in DOM order
  - destructive actions should not sit beside the primary submit unless the flow truly
    requires it
- Keep naming explicit:
  - `Create X` for new records
  - `Save Changes` or `Update X` for edits
  - avoid vague labels like `Submit` unless the domain language specifically needs it

### Tables, Cards, and Dense Operator Screens

- Do not force wide data tables onto mobile without an alternate presentation.
- For narrow screens, prefer one of:
  - stacked cards
  - horizontally scrollable table containers
  - reduced column sets with key actions preserved
- Stat cards, action cards, and queue cards must use compact mobile spacing and should not
  assume large icon blocks or oversized desktop typography.
- When building operator consoles, prioritize:
  - scanability
  - clear primary actions
  - visible status/state
  - low-friction mobile tap targets

### Uniformity Expectations

- Before creating a new layout pattern, check for an existing shared component that should
  be extended instead.
- If you touch one shared component for responsiveness or visual consistency, consider
  whether sibling shared components should be aligned in the same pass.
- Do not ship a screen that looks polished on desktop but broken, crowded, or accidental on
  mobile.
- When making UI changes, verify both:
  - visual consistency with existing shared components
  - responsive behavior at small and large widths
- For the acquisition human-review experience, use terms like "queue",
  "review workspace", "operator view", or "intake review". Do not call it a
  cockpit in UI copy, docs, commit messages, or summaries.

## Development Workflow

1. **I run the server** - Don't start/stop Phoenix
2. **Generate migrations**: `mix ash.codegen`
3. **Apply migrations**: `mix ash.migrate`
4. **Before committing**: `mix precommit`

## Code Shape

- If a file grows past roughly 500 lines, treat it as a design smell and look
  for obvious extraction points before adding much more behavior.
- If a file reaches roughly 2000 lines, that is a hard cutoff: split it into
  focused modules or components before continuing feature work in that file.
- Prefer domain-local folders over generic helper buckets.
- Repeated label, filter, sorting, ownership, or status logic is usually a sign
  that the resource needs a calculation, preparation, action, or shared
  domain-local module.

## Dev Routes

| Path | Description |
|------|-------------|
| `/admin` | Ash Admin panel |
| `/oban` | Oban Web dashboard |
| `/dev/dashboard` | Phoenix LiveDashboard |
| `/dev/mailbox` | Swoosh mailbox preview |

## Project Structure

```
lib/
  gnome_garden/
    accounts/           # Auth domain
      user.ex
      token.ex
    accounts.ex         # Domain module
    repo.ex
  gnome_garden_web/
    live/               # LiveViews
    components/         # Components
    router.ex
```

## Common Mix Tasks Reference

```bash
# Ash
mix ash.codegen              # Generate migrations for resource changes
mix ash.migrate              # Run Ash migrations
mix ash.reset                # Drop, create, migrate
mix ash.gen.resource         # Generate new resource
mix ash.gen.domain           # Generate new domain
mix ash.extend               # Add extension to resource

# Phoenix
mix phx.routes               # List all routes
mix phx.gen.live             # Generate LiveView (but prefer Ash patterns)

# Testing
mix test                     # Run tests
mix test --failed            # Re-run failed tests
mix test path:line           # Run specific test

# Quality
mix precommit                # Format, compile warnings, test
mix format                   # Format code
```

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->


<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `gnome_garden_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use GnomeGardenWeb, :html`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `GnomeGardenWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `GnomeGardenWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
