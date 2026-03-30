# Sales CRM Domain Implementation

## Problem
Build a Sales CRM domain with Company, Contact, Industry, Activity, Note, Address, and CompanyRelationship resources using Ash Framework.

## Solution

### Domain Structure
```
lib/gnome_garden/sales/
├── sales.ex              # Domain module
├── industry.ex           # Industry classification
├── company.ex            # Organizations (customers, partners, vendors)
├── contact.ex            # People at companies
├── activity.ex           # Interaction tracking (calls, emails, meetings)
├── note.ex               # Polymorphic notes
├── address.ex            # Separate address table
└── company_relationship.ex # Company-to-company relationships
```

### Key Patterns

#### 1. Polymorphic Notes
Using `notable_type` + `notable_id` pattern for attaching notes to any CRM record:

```elixir
attribute :notable_type, :string do
  allow_nil? false
  public? true
end

attribute :notable_id, :uuid do
  allow_nil? false
  public? true
end
```

#### 2. Self-Referential Relationships with Validation
Preventing companies from having relationships with themselves:

```elixir
validate fn changeset, _context ->
  from_id = Ash.Changeset.get_attribute(changeset, :from_company_id)
  to_id = Ash.Changeset.get_attribute(changeset, :to_company_id)

  if from_id && to_id && from_id == to_id do
    {:error, field: :to_company_id, message: "a company cannot have a relationship with itself"}
  else
    :ok
  end
end
```

#### 3. Bidirectional Company Relationships
Using two belongs_to relationships and a read action that queries both directions:

```elixir
read :by_company do
  argument :company_id, :uuid, allow_nil?: false
  filter expr(from_company_id == ^arg(:company_id) or to_company_id == ^arg(:company_id))
end
```

#### 4. Case-Insensitive Email
Using `:ci_string` type for email fields:

```elixir
attribute :email, :ci_string do
  public? true
end
```

### Configuration
Add domain to `config/config.exs`:
```elixir
ash_domains: [GnomeGarden.Accounts, GnomeGarden.Agents, GnomeGarden.Sales]
```

## Tags
ash, crm, sales, polymorphic, self-referential, validation
