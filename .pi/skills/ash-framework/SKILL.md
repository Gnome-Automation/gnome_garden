---
name: ash-framework
description: Ash Framework idiomatic patterns, anti-patterns, and mix task references for Elixir/Phoenix projects. Use when creating or modifying Ash resources, domains, actions, relationships, policies, migrations, forms, or LiveViews that interact with Ash data.
---

# Ash Framework — Idiomatic Practices

Load this skill when working with Ash resources, domains, actions, policies, migrations, or any LiveView/component that reads or writes Ash-managed data.

## Critical Rules

These rules override any tendency to fall back to raw Ecto or hand-rolled patterns.

### 1. Never Use Repo Directly

```
# WRONG
GnomeGarden.Repo.all(MyResource)
GnomeGarden.Repo.insert(%MyResource{name: "foo"})
Ecto.Changeset.cast(...)

# CORRECT — use code interfaces (preferred)
GnomeGarden.MyDomain.list_resources()
GnomeGarden.MyDomain.create_resource(%{name: "foo"})

# CORRECT — use Ash directly when no code interface exists
Ash.read!(MyResource)
Ash.create!(MyResource, %{name: "foo"})
```

### 2. Never Write Functions When Ash Has a DSL Feature

| If you need… | Use this Ash feature |
|---|---|
| Set a field on create/update | `change set_attribute(:field, value)` |
| Default value for new records | `attribute :status, :atom, default: :draft` |
| Derive a value | `calculate :full_name, :string, expr(first_name <> " " <> last_name)` |
| Count/sum related records | `count :comment_count, :comments` or `sum :total, :line_items, :amount` |
| Filter reads | `filter expr(status == :published)` in a preparation |
| Sort reads | `prepare build(sort: [inserted_at: :desc])` |
| Validate input | `validations` block with `validate present(:title)` etc. |
| Set current user | `change relate_actor(:user)` |
| Manage nested relationships | `change manage_relationship(:tags, type: :append)` |
| Atomic increment | `change increment(:view_count)` |
| Scope reads to actor | `prepare filter expr(user_id == ^actor(:id))` |

### 3. Migrations — Always Use Ash Workflow

```bash
# Generate migrations from resource changes
mix ash.codegen descriptive_name

# Apply migrations
mix ash.migrate

# Full reset (drop + create + migrate + seed)
mix ash.reset

# NEVER do these for Ash resources:
# mix ecto.gen.migration   ← WRONG
# mix ecto.migrate         ← WRONG
```

### 4. Pass actor: user Everywhere

Authorization policies won't work without an actor. Always pass `actor:` in:

- Code interface calls: `GnomeGarden.Content.list_posts(actor: current_user)`
- LiveView mounts and event handlers
- Tests (or use `actor: nil` explicitly when testing unauthorized access)
- Background jobs (resolve the actor and pass it through)

## Resource Template

Every new resource should follow this skeleton:

```elixir
defmodule GnomeGarden.MyDomain.MyResource do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.MyDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: []

  postgres do
    table "my_resources"
    repo GnomeGarden.Repo

    references do
      # Always declare foreign key references
      # reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    # Add custom actions here
  end

  policies do
    # Define authorization policies
  end

  attributes do
    uuid_primary_key :id
    # timestamps are added by defaults, or:
    # create_timestamp :inserted_at
    # update_timestamp :updated_at
  end

  relationships do
    # belongs_to, has_many, many_to_many
  end

  identities do
    # unique constraints
  end

  calculations do
    # derived values
  end

  aggregates do
    # counts, sums, etc.
  end
end
```

## Domain Template with Code Interfaces

Every domain resource must expose code interfaces:

```elixir
defmodule GnomeGarden.MyDomain do
  use Ash.Domain, otp_app: :gnome_garden, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.MyDomain.MyResource do
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

## Action Patterns

### Custom Read with Arguments

```elixir
# Search with argument
read :search do
  argument :query, :string, allow_nil?: false
  filter expr(contains(name, ^arg(:query)))
end

# Single-record read (returns {:ok, record} or {:error, :not_found})
read :get_by_email do
  get_by :email
end
```

### Custom Read with Filtering and Sorting

```elixir
read :published do
  filter expr(status == :published)
  prepare build(sort: [inserted_at: :desc])
  prepare build(load: [:author, :comment_count])
end
```

### Create with Side Effects

```elixir
create :register do
  accept [:email, :name]
  change set_attribute(:status, :pending)
  change {MyApp.Changes.SendWelcomeEmail, []}
end
```

### Update with State Machine

```elixir
update :publish do
  require_atomic? false
  change transition_state(:published)
  change set_attribute(:published_at, &DateTime.utc_now/0)
end
```

### Built-in Changes Quick Reference

```elixir
change set_attribute(:field, value)                     # Set fixed value
change set_attribute(:field, &DateTime.utc_now/0)      # Set from function
change set_new_attribute(:field, value)                 # Only if not already set
change relate_actor(:user)                              # Set relationship to actor
change manage_relationship(:tags, type: :append)        # Manage nested data
change increment(:view_count)                           # Atomic increment
change filter expr(author_id == ^actor(:id))            # Scope to actor
change after_action(fn cs, record, _ctx -> ... end)     # Post-commit hook
```

### Built-in Preparations Quick Reference

```elixir
prepare build(sort: [inserted_at: :desc])               # Default sort
prepare build(load: [:author, :comments])               # Eager load
prepare build(limit: 10)                                # Limit results
prepare filter expr(status == :active)                  # Filter results
prepare filter expr(user_id == ^actor(:id))             # Scope to actor
```

### Generic Action (Not CRUD)

```elixir
action :send_notification, :boolean do
  argument :message, :string, allow_nil?: false
  run fn input, _context ->
    {:ok, true}
  end
end
```

## Validations

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

## Relationship Patterns

```elixir
relationships do
  # Simple belongs_to
  belongs_to :user, GnomeGarden.Accounts.User do
    allow_nil? false
  end

  # has_many with explicit destination attribute
  has_many :comments, GnomeGarden.Content.Comment do
    destination_attribute :post_id
  end

  # many_to_many through join resource
  many_to_many :tags, GnomeGarden.Content.Tag do
    through GnomeGarden.Content.PostTag
    source_attribute_on_join_resource :post_id
    destination_attribute_on_join_resource :tag_id
  end
end
```

## AshStorage and Shared Documents

The `ash_storage` extension gives you one host resource to one file, or one host to many files.
When the same file applies to multiple parents, or the link has its own metadata, model it
explicitly instead of forcing the attachment primitive.

### Architecture

- **Dedicated blob resource** — holds the file metadata, has `ash_storage` on it
- **Attachment resource** — join between blob and host, holds relationship-specific metadata
- **Host resource** — `has_one_attached` / `has_many_attached` for simple cases

### When to Use Join Resources

Use a join resource (e.g., `FindingDocument`, `ParentRecordDocument`) when:
- The same file needs to apply to multiple parent records
- The parent-to-file link has its own metadata (`is_primary`, `effective_on`, `notes`,
  `document_role`, `required_for_promotion`, etc.)
- Keep those fields on the **join resource**, not on the blob

### Through Relationships — Know the Difference

| Pattern | Use When | Writable? |
|---|---|---|
| `many_to_many ... through: JoinResource` | Real many-to-many with join metadata | Yes |
| `has_many/has_one ... through: [:join, :dest]` | Read-only shortcut to final records | No |

Do **not** confuse these two `through` features.

### Practical Guidance

```elixir
# Standard setup: one blob, one attachment, one or more hosts
# Host resource:
has_one_attached :avatar do
  ...  # ash_storage macro
end

# Shared attachments: attachment can declare multiple belongs_to_resource
# Polymorphic: omit belongs_to_resource, use generic attachment pattern
```

- **Direct uploads for large files**: `AshStorage.Operations.prepare_direct_upload/3` + `AshStorage.Changes.AttachBlob`
- **Simpler flows**: `AshStorage.Changes.HandleFileArgument` with `Ash.Type.File`
- **In tests**: switch to `AshStorage.Service.Test` and reset between tests

## AshOban (Background Jobs)

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

## Policy Patterns

```elixir
policies do
  # Admins bypass everything
  bypass actor_attribute_equals(:role, :admin) do
    authorize_if always()
  end

  # Read published resources or your own
  policy action_type(:read) do
    authorize_if expr(status == :published)
    authorize_if relates_to_actor_via(:author)
  end

  # Only author can update/destroy
  policy action_type([:update, :destroy]) do
    authorize_if relates_to_actor_via(:author)
  end

  # Deny everything else
  policy always() do
    forbid_if always()
  end
end
```

## AshPhoenix Forms in LiveViews

```elixir
# Create form
form =
  MyResource
  |> AshPhoenix.Form.for_create(:create,
    actor: socket.assigns.current_user,
    forms: [auto?: true]
  )
  |> to_form()

# Update form
form =
  record
  |> AshPhoenix.Form.for_update(:update,
    actor: socket.assigns.current_user,
    forms: [auto?: true]
  )
  |> to_form()

# Handle validate
def handle_event("validate", %{"form" => params}, socket) do
  form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
  {:noreply, assign(socket, form: to_form(form))}
end

# Handle submit
def handle_event("save", %{"form" => params}, socket) do
  case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
    {:ok, record} ->
      {:noreply, push_navigate(socket, to: ~p"/resources/#{record.id}")}

    {:error, form} ->
      {:noreply, assign(socket, form: to_form(form))}
  end
end
```

## Calculations and Aggregates

```elixir
calculations do
  # Expression calculation
  calculate :full_name, :string, expr(first_name <> " " <> last_name)

  # With SQL fragment
  calculate :initials, :string, expr(
    fragment("substring(? from 1 for 1) || substring(? from 1 for 1)",
             first_name, last_name)
  )

  # Module calculation for complex logic
  calculate :avatar_url, :string, {MyApp.Calculations.AvatarUrl, []}

  # Status badge variant for UI
  calculate :status_variant, :atom, expr(
    case status do
      :draft -> :default
      :published -> :success
      :archived -> :muted
    end
  )
end

aggregates do
  count :comment_count, :comments
  count :published_comments, :comments do
    filter expr(status == :published)
  end
  sum :total_amount, :line_items, :amount
  first :latest_comment_body, :comments, :body do
    sort inserted_at: :desc
  end
  list :tag_names, :tags, :name
end
```

## Loading Relationships and Calculations

```elixir
# Eager load in code interface call
GnomeGarden.Content.get_post!(id, load: [:author, :comments, :comment_count])

# Load after the fact
post = Ash.load!(post, [:author, :comment_count])

# Nested loading
Ash.load!(post, [comments: [:author]])

# In action preparation (always loaded)
read :with_details do
  prepare build(load: [:author, :comment_count, comments: [:author]])
end
```

## AshStateMachine

```elixir
# In resource: use AshStateMachine extension
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
end
```

## Testing Ash Resources

```elixir
defmodule GnomeGarden.Content.PostTest do
  use GnomeGarden.DataCase

  test "creates with valid attrs" do
    user = user_fixture()

    assert {:ok, post} =
      GnomeGarden.Content.create_post(
        %{title: "Test", body: "Content"},
        actor: user
      )

    assert post.title == "Test"
  end

  test "forbids without actor" do
    assert {:error, %Ash.Error.Forbidden{}} =
      GnomeGarden.Content.create_post(%{title: "Test"})
  end

  test "validation errors" do
    assert {:error, %Ash.Error.Invalid{}} =
      GnomeGarden.Content.create_post(%{}, actor: user_fixture())
  end
end
```

## Common Mix Tasks

```bash
# Migrations
mix ash.codegen <name>        # Generate migration from resource changes
mix ash.migrate               # Run Ash migrations
mix ash.reset                 # Drop, create, migrate, seed
mix ash.rollback              # Rollback last migration

# Code generation
mix ash.gen.resource MyDomain.MyResource --domain GnomeGarden.MyDomain --attribute name:string
mix ash.gen.domain MyDomain
mix ash.extend GnomeGarden.MyDomain.MyResource AshStateMachine

# Documentation lookup (project-specific)
mix usage_rules.docs Ash.Resource
mix usage_rules.docs Ash.Changeset.for_create/4
mix usage_rules.search_docs "code interface"
mix usage_rules.search_docs "belongs_to" -p ash

# Architecture map (project-specific)
mix llm.generate_resource_map

# Phoenix
mix phx.routes                # List all routes

# Quality
mix precommit                 # Format, compile warnings, test
mix format                    # Format code
mix test                      # Run tests
mix test --failed             # Re-run failed tests
mix test path/to/test.exs:123  # Run specific test
```

## Documentation Lookup Workflow

When implementing any Ash feature, follow this order:

1. **Check the architecture map** — Read `docs/llm/index.md` and `docs/llm/generated/resources.json` for what's already implemented. Check `config/config.exs` under `config :gnome_garden, :ash_domains` for registered domains. Treat these as authoritative.
2. **Distinguish planned vs implemented** — Files under `documentation/architecture/` and `documentation/domains/` may be aspirational. Only trust what appears in `docs/llm/generated/resources.json`.
3. **Search Ash docs** — Use `mix usage_rules.search_docs "feature"` to find relevant documentation
4. **Check module docs** — Use `mix usage_rules.docs Some.Module` or `mix usage_rules.docs Some.Module.function/arity`
5. **Apply the DSL** — Use the declarative Ash DSL instead of writing functions
6. **Refresh the architecture map** — After changing any domain or resource, run `mix llm.generate_resource_map`
7. **Generate migrations** — Run `mix ash.codegen descriptive_name`
8. **Run quality checks** — Run `mix precommit` before committing

## Common Anti-Patterns Checklist

Before submitting any Ash-related code, verify:

- [ ] No direct `Repo` calls — all data access through code interfaces or `Ash.*` functions
- [ ] No `Ecto.Changeset` usage — use Ash actions and changes
- [ ] No `Enum.filter` / `Enum.sort` in LiveViews — use preparations with `filter` and `build(sort:)`
- [ ] No hand-rolled count/sum functions — use aggregates
- [ ] No computed values in templates — use calculations
- [ ] No manual foreign key management — use relationships
- [ ] `actor:` passed to all actions that need authorization
- [ ] `postgres.references` block has all foreign key references declared
- [ ] Code interfaces defined in the domain for all resource actions
- [ ] `require_atomic? false` only used when genuinely needed for complex changes
- [ ] AshStorage: dedicated blob + attachment resources, join metadata on join resource not blob
- [ ] AshOban: triggers use `where` expressions, scheduled actions use cron syntax
- [ ] Calculations for UI badge variants (`status_variant`, `priority_color`) — not scattered helpers

## Presentation-Facing Derived Values

When a resource has a lifecycle field (`status`, `stage`, `priority`) and the UI needs a stable
badge variant (`:default`, `:info`, `:warning`, `:success`, `:error`), model that as a calculation
on the resource:

```elixir
calculate :status_variant, :atom, expr(
  case status do
    :draft -> :default
    :published -> :success
    :archived -> :muted
  end
end)
```

Load from the domain and use in templates. Do **not** scatter one-off helper functions across
the web layer for status-to-badge or stage-to-color mappings.

## See Also

- [Ash Resource Reference](references/resource-fields.md) — Complete attribute type and constraint reference
- [Ash Error Handling](references/error-handling.md) — Error patterns and LiveView integration
