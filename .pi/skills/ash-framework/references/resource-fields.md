# Ash Resource Attribute Types and Constraints

## Attribute Types

| Type | Example | Notes |
|------|---------|-------|
| `:uuid` | `uuid_primary_key :id` | Default primary key type |
| `:string` | `attribute :name, :string` | Maps to `varchar` |
| `:integer` | `attribute :count, :integer` | |
| `:float` | `attribute :rate, :float` | |
| `:boolean` | `attribute :active, :boolean, default: false` | |
| `:atom` | `attribute :status, :atom` | Requires `constraints one_of: [...]` |
| `:map` | `attribute :metadata, :map` | JSONB in Postgres |
| `:decimal` | `attribute :price, :decimal` | Use for money |
| `:date` | `attribute :born_on, :date` | |
| `:time` | `attribute :opens_at, :time` | |
| `:utc_datetime` | `attribute :published_at, :utc_datetime` | |
| `:naive_datetime` | `attribute :happened_at, :naive_datetime` | |
| `:duration` | `attribute :length, :duration` | |
| `:binary` | `attribute :data, :binary` | Bytea in Postgres |
| `:ci_string` | `attribute :email, :ci_string` | Case-insensitive comparisons |
| `:union` | `attribute :value, :union` | Polymorphic, requires constraints |

## Common Constraints

```elixir
attribute :email, :ci_string do
  allow_nil? false
  constraints min_length: 5, max_length: 255
end

attribute :status, :atom do
  constraints one_of: [:draft, :published, :archived]
  default :draft
  allow_nil? false
end

attribute :price, :decimal do
  constraints precision: 10, scale: 2
end

attribute :tags, {:array, :string} do
  default []
end
```

## Primary Keys

```elixir
# UUID primary key (standard)
uuid_primary_key :id

# Auto-increment integer primary key
integer_primary_key :id

# Composite primary key (use sparingly)
# Requires custom logic
```

## Timestamps

```elixir
# These are added automatically by defaults, but can be explicit:
create_timestamp :inserted_at
update_timestamp :updated_at
```

## Sensitive Attributes

```elixir
# Won't be included in API responses by default
attribute :api_key, :string do
  sensitive? true
end
```

## Public vs Private

```elixir
# Public attributes are accessible via API
attribute :title, :string do
  public? true  # Required for accepting input via :* accept patterns
end

# Private attributes are internal only
attribute :internal_flag, :boolean do
  public? false
end
```
