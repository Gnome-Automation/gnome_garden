# Navigation

## Route Structure

All routes are organized by domain with consistent patterns.

---

## Route Map

### Public Routes
| Route | Component | Description |
|-------|-----------|-------------|
| `/` | HomePage | Landing page |
| `/sign-in` | AuthLive | Magic link login |
| `/auth` | AuthCallback | Token validation |

### Dashboard
| Route | Component | Description |
|-------|-----------|-------------|
| `/dashboard` | DashboardLive | Main dashboard |

### Workspace
| Route | Component | Description |
|-------|-----------|-------------|
| `/capture` | CaptureLive | Quick capture |
| `/inbox` | InboxLive | Inbox queue |
| `/reminders` | ReminderLive | Reminders |

### CRM
| Route | Component | Description |
|-------|-----------|-------------|
| `/companies` | CompanyLive.Index | Company list |
| `/companies/new` | CompanyLive.Form | Create company |
| `/companies/:id` | CompanyLive.Show | Company detail |
| `/companies/:id/edit` | CompanyLive.Form | Edit company |
| `/contacts` | ContactLive.Index | Contact list |
| `/contacts/new` | ContactLive.Form | Create contact |
| `/contacts/:id` | ContactLive.Show | Contact detail |
| `/contacts/:id/edit` | ContactLive.Form | Edit contact |
| `/activities` | ActivityLive | Activity feed |

### Sales
| Route | Component | Description |
|-------|-----------|-------------|
| `/opportunities` | OpportunityLive.Index | Pipeline |
| `/opportunities/new` | OpportunityLive.Form | Create opp |
| `/opportunities/:id` | OpportunityLive.Show | Opp detail |
| `/proposals` | ProposalLive.Index | Proposal list |
| `/proposals/new` | ProposalLive.Form | Create proposal |
| `/proposals/:id` | ProposalLive.Show | Proposal detail |
| `/contracts` | ContractLive.Index | Contract list |
| `/contracts/:id` | ContractLive.Show | Contract detail |
| `/services` | ServiceLive | Service catalog |

### Delivery
| Route | Component | Description |
|-------|-----------|-------------|
| `/projects` | ProjectLive.Index | Project list |
| `/projects/new` | ProjectLive.Form | Create project |
| `/projects/:id` | ProjectLive.Show | Project detail |
| `/projects/:id/board` | TaskBoard | Kanban view |
| `/tasks` | TaskLive.Index | All tasks |
| `/time` | TimeEntryLive | Timesheet |
| `/team` | MemberLive.Index | Team roster |
| `/schedule` | ScheduleLive | Resource view |

### Finance
| Route | Component | Description |
|-------|-----------|-------------|
| `/invoices` | InvoiceLive.Index | Invoice list |
| `/invoices/new` | InvoiceLive.Form | Create invoice |
| `/invoices/:id` | InvoiceLive.Show | Invoice detail |
| `/payments` | PaymentLive | Payments |
| `/subscriptions` | SubscriptionLive | Subscriptions |
| `/expenses` | ExpenseLive | Expenses |

### Support
| Route | Component | Description |
|-------|-----------|-------------|
| `/tickets` | TicketLive.Index | Ticket queue |
| `/tickets/new` | TicketLive.Form | Create ticket |
| `/tickets/:id` | TicketLive.Show | Ticket detail |
| `/kb` | ArticleLive.Index | Knowledge base |
| `/kb/:slug` | ArticleLive.Show | Article view |
| `/slas` | SLALive | SLA management |

### Engineering
| Route | Component | Description |
|-------|-----------|-------------|
| `/assets` | AssetLive.Index | Asset list |
| `/assets/new` | AssetLive.Form | Create asset |
| `/assets/:id` | AssetLive.Show | Asset detail |
| `/plants` | PlantLive.Index | Plant list |
| `/plants/:id` | PlantLive.Show | Plant detail |
| `/boms` | BOMLive.Index | BOM list |
| `/boms/:id` | BOMLive.Show | BOM detail |
| `/templates` | TemplateLive | Logic templates |

### Agents
| Route | Component | Description |
|-------|-----------|-------------|
| `/agents` | AgentLive | Agent management |
| `/bids` | BidLive | Bid dashboard |
| `/sources` | LeadSourceLive | Lead sources |

### Admin
| Route | Component | Description |
|-------|-----------|-------------|
| `/admin` | AshAdmin | Admin dashboard |
| `/oban` | ObanWeb | Job queue |
| `/settings` | SettingsLive | User settings |

---

## Menu Hierarchy

### Primary Navigation (Sidebar)
```
Dashboard
├── Overview

Work
├── Inbox
├── Projects
├── Tasks
└── Time

Relationships
├── Companies
├── Contacts
└── Activities

Revenue
├── Opportunities
├── Proposals
├── Contracts
└── Invoices

Support
├── Tickets
└── Knowledge Base

Engineering
├── Assets
├── Plants
├── BOMs
└── Templates

AI
├── Agents
├── Bids
└── Sources

Settings
└── Account
```

### Mobile Bottom Nav
```
[Home] [Projects] [Inbox] [Money] [More]
                              │
                              └── Expands to:
                                  - Companies
                                  - Contacts
                                  - Support
                                  - Engineering
                                  - Settings
```

---

## Deep Linking

### URL Parameters
| Pattern | Example | Usage |
|---------|---------|-------|
| Resource ID | `/companies/abc123` | Direct resource |
| Tab | `/companies/abc123?tab=contacts` | Active tab |
| Filter | `/tasks?status=in_progress` | List filtering |
| Page | `/companies?page=2` | Pagination |
| Search | `/contacts?q=john` | Search query |

### Examples
```
# View company with contacts tab active
/companies/abc123?tab=contacts

# Filter tasks by status and assignee
/tasks?status=in_progress&assignee=me

# Search contacts at specific company
/contacts?company_id=abc123&q=john

# View second page of overdue invoices
/invoices?status=overdue&page=2
```

---

## Router Implementation

```elixir
# lib/gnome_garden_web/router.ex

defmodule GnomeGardenWeb.Router do
  use GnomeGardenWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GnomeGardenWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Public routes
  scope "/", GnomeGardenWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Auth routes handled by AshAuthentication
  end

  # Authenticated routes
  scope "/", GnomeGardenWeb do
    pipe_through [:browser, :require_authenticated_user]

    ash_authentication_live_session :authenticated_routes do
      # Dashboard
      live "/dashboard", DashboardLive

      # Workspace
      live "/capture", CaptureLive
      live "/inbox", InboxLive
      live "/reminders", ReminderLive

      # CRM
      live "/companies", CompanyLive.Index
      live "/companies/new", CompanyLive.Form, :new
      live "/companies/:id", CompanyLive.Show
      live "/companies/:id/edit", CompanyLive.Form, :edit
      # ... more routes
    end
  end

  # Admin routes
  scope "/admin" do
    pipe_through [:browser, :require_admin]

    import AshAdmin.Router
    ash_admin "/"
  end

  # Oban dashboard
  scope "/oban" do
    pipe_through [:browser, :require_admin]

    import Oban.Web.Router
    oban_dashboard "/"
  end
end
```

---

## LiveView Navigation

### Push Navigate
```elixir
# Full page navigation
{:noreply, push_navigate(socket, to: ~p"/companies/#{company}")}
```

### Push Patch
```elixir
# Update URL without full reload
{:noreply, push_patch(socket, to: ~p"/companies?#{params}")}
```

### Handle Params
```elixir
def handle_params(params, _uri, socket) do
  socket =
    socket
    |> assign(:page, params["page"] || 1)
    |> assign(:search, params["q"])
    |> load_data()

  {:noreply, socket}
end
```

---

## Breadcrumbs

### Component
```elixir
attr :items, :list, required: true

def breadcrumb(assigns) do
  ~H"""
  <div class="text-sm breadcrumbs">
    <ul>
      <li><a href="/"><.icon name="hero-home" class="h-4 w-4" /></a></li>
      <%= for item <- @items do %>
        <li>
          <%= if item[:href] do %>
            <a href={item.href}><%= item.label %></a>
          <% else %>
            <%= item.label %>
          <% end %>
        </li>
      <% end %>
    </ul>
  </div>
  """
end
```

### Usage
```heex
<.breadcrumb items={[
  %{label: "CRM", href: ~p"/crm"},
  %{label: "Companies", href: ~p"/companies"},
  %{label: @company.name}
]} />
```

---

## Mobile Navigation Patterns

### Slide-out Menu
```heex
<div class="drawer lg:drawer-open">
  <input id="nav-drawer" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content">
    <!-- Page content -->
  </div>
  <div class="drawer-side z-50">
    <label for="nav-drawer" class="drawer-overlay"></label>
    <aside class="bg-base-100 w-64 min-h-screen">
      <!-- Menu content -->
    </aside>
  </div>
</div>
```

### Back Button
```heex
<.link navigate={@back_path} class="btn btn-ghost btn-sm">
  <.icon name="hero-arrow-left" class="h-5 w-5" />
  Back
</.link>
```

### Swipe Gestures
```javascript
// Alpine.js swipe detection
x-on:touchstart="touchStart($event)"
x-on:touchend="touchEnd($event)"
```
