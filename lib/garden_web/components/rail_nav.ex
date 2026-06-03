defmodule GnomeGardenWeb.Components.RailNav do
  @moduledoc """
  Rail + tabs navigation chrome.

  Components:
    * `rail/1`        — skinny vertical rail of areas (desktop)
    * `area_header/1` — "AREA · Procurement · 2 open" strip above tabs
    * `tab_strip/1`   — per-area tabs (one per destination in that area)
    * `mobile_top/1`  — compact mobile top bar
    * `mobile_bar/1`  — mobile bottom area bar
    * `mobile_sheet/1`— mobile area sheet (shown via JS toggle)
    * `leaf_icon/1`   — brand mark

  Helpers:
    * `area_for_path/1`   — derives current area from request path
    * `active_dest/2`     — destination matching current path (or first in area)
    * `area_dests/1`      — destinations in a given area
    * `area_has_hot?/1`   — true if any dest in area has `hot: true`
    * `destinations/0`    — full catalog
  """
  use Phoenix.Component

  import GnomeGardenWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @rail_areas [
    %{id: "Workspace", icon: "hero-home", label: "Workspace"},
    %{id: "Acquisition", icon: "hero-inbox-stack", label: "Acquisition"},
    %{id: "Procurement", icon: "hero-viewfinder-circle", label: "Procurement"},
    %{id: "Commercial", icon: "hero-rocket-launch", label: "Commercial"},
    %{id: "Operations", icon: "hero-building-office", label: "Operations"},
    %{id: "Finance", icon: "hero-banknotes", label: "Finance"},
    %{id: "Reports", icon: "hero-chart-bar", label: "Reports"},
    %{id: "Settings", icon: "hero-cog-6-tooth", label: "Settings"}
  ]

  @bottom_areas [
    %{id: "Acquisition", icon: "hero-inbox-stack", label: "Acquire"},
    %{id: "Commercial", icon: "hero-rocket-launch", label: "Pursue"},
    %{id: "Operations", icon: "hero-building-office", label: "Ops"},
    %{id: "Finance", icon: "hero-banknotes", label: "Finance"},
    %{id: "more", icon: "hero-ellipsis-horizontal", label: "More"}
  ]

  # `path` is the canonical destination URL — clicking a tab navigates here.
  # `match` is a list of path *prefixes* that count as "active" (defaults to [path]).
  @destinations [
    # Workspace
    %{
      id: "home",
      section: "Workspace",
      icon: "hero-home",
      label: "Home",
      tooltip: "Overview dashboard — open items, activity, and quick stats",
      path: "/",
      badge: 0,
      hot: false,
      match: ["/"]
    },
    %{
      id: "agent",
      section: "Workspace",
      icon: "hero-sparkles",
      label: "Agent",
      tooltip: "AI agent — run autonomous tasks, research, and workflows",
      path: "/agent",
      badge: 0,
      hot: false,
      match: ["/agent"]
    },

    # Acquisition
    %{
      id: "acq-queue",
      section: "Acquisition",
      icon: "hero-inbox-arrow-down",
      label: "Review queue",
      tooltip: "Incoming bids and leads waiting for a pursue or pass decision",
      path: "/acquisition/findings",
      badge: 0,
      hot: false,
      match: ["/acquisition/findings"]
    },
    %{
      id: "acq-sources",
      section: "Acquisition",
      icon: "hero-globe-alt",
      label: "Sources",
      tooltip: "Bid sources and portals the agent monitors for new opportunities",
      path: "/acquisition/sources",
      badge: 0,
      hot: false,
      match: ["/acquisition/sources"]
    },
    %{
      id: "acq-programs",
      section: "Acquisition",
      icon: "hero-academic-cap",
      label: "Programs",
      tooltip: "Discovery programs — saved search configs the agent runs on a schedule",
      path: "/acquisition/programs",
      badge: 0,
      hot: false,
      match: ["/acquisition/programs"]
    },

    # Procurement
    %{
      id: "proc-targeting",
      section: "Procurement",
      icon: "hero-viewfinder-circle",
      label: "Targeting",
      tooltip: "Subcontractor and vendor targeting — identify and track potential partners",
      path: "/procurement/targeting",
      badge: 0,
      hot: false,
      match: ["/procurement/targeting"]
    },

    # Commercial
    %{
      id: "com-pursuits",
      section: "Commercial",
      icon: "hero-rocket-launch",
      label: "Pursuits",
      tooltip: "Active opportunities being worked through the sales pipeline",
      path: "/commercial/pursuits",
      badge: 0,
      hot: false,
      match: ["/commercial/pursuits"]
    },
    %{
      id: "com-signal",
      section: "Commercial",
      icon: "hero-bolt",
      label: "Signals",
      tooltip: "Market signals — intelligence items that may indicate new opportunities",
      path: "/commercial/signals",
      badge: 0,
      hot: false,
      match: ["/commercial/signals"]
    },
    %{
      id: "com-deals",
      section: "Commercial",
      icon: "hero-banknotes",
      label: "Agreements",
      tooltip: "Signed service agreements — active contracts with billing terms and schedules",
      path: "/commercial/agreements",
      badge: 0,
      hot: false,
      match: ["/commercial/agreements"]
    },
    %{
      id: "com-proposals",
      section: "Commercial",
      icon: "hero-document-text",
      label: "Proposals",
      tooltip: "Proposals sent to clients — track status from draft through accepted",
      path: "/commercial/proposals",
      badge: 0,
      hot: false,
      match: ["/commercial/proposals"]
    },
    %{
      id: "com-programs",
      section: "Commercial",
      icon: "hero-academic-cap",
      label: "Programs",
      tooltip: "Discovery programs linked to commercial opportunities",
      path: "/commercial/discovery-programs",
      badge: 0,
      hot: false,
      match: ["/commercial/discovery-programs"]
    },
    %{
      id: "com-changeorders",
      section: "Commercial",
      icon: "hero-arrow-path",
      label: "Change orders",
      tooltip: "Scope changes to existing agreements — track approvals and billing impacts",
      path: "/commercial/change-orders",
      badge: 0,
      hot: false,
      match: ["/commercial/change-orders"]
    },

    # Operations
    %{
      id: "ops-orgs",
      section: "Operations",
      icon: "hero-building-office-2",
      label: "Organizations",
      tooltip: "Client and partner companies — CRM records with contacts and billing info",
      path: "/operations/organizations",
      badge: 0,
      hot: false,
      match: ["/operations/organizations"]
    },
    %{
      id: "ops-people",
      section: "Operations",
      icon: "hero-users",
      label: "People",
      tooltip: "Individual contacts — employees, clients, and decision makers",
      path: "/operations/people",
      badge: 0,
      hot: false,
      match: ["/operations/people"]
    },
    %{
      id: "ops-sites",
      section: "Operations",
      icon: "hero-map-pin",
      label: "Sites",
      tooltip: "Physical locations where work is performed or equipment is installed",
      path: "/operations/sites",
      badge: 0,
      hot: false,
      match: ["/operations/sites"]
    },
    %{
      id: "ops-systems",
      section: "Operations",
      icon: "hero-cpu-chip",
      label: "Systems",
      tooltip: "Managed systems — PLCs, control panels, and equipment under service contracts",
      path: "/operations/managed-systems",
      badge: 0,
      hot: false,
      match: ["/operations/managed-systems"]
    },
    %{
      id: "ops-assets",
      section: "Operations",
      icon: "hero-cube",
      label: "Assets",
      tooltip: "Individual assets tied to systems or sites — tracked hardware and equipment",
      path: "/operations/assets",
      badge: 0,
      hot: false,
      match: ["/operations/assets"]
    },
    %{
      id: "ops-affiliations",
      section: "Operations",
      icon: "hero-link",
      label: "Affiliations",
      tooltip: "Relationships between people and organizations — roles, titles, and contacts",
      path: "/operations/affiliations",
      badge: 0,
      hot: false,
      match: ["/operations/affiliations"]
    },
    %{
      id: "ops-projects",
      section: "Operations",
      icon: "hero-clipboard-document-list",
      label: "Projects",
      tooltip: "Active projects — scoped work with tasks, timelines, and team assignments",
      path: "/execution/projects",
      badge: 0,
      hot: false,
      match: ["/execution/projects"]
    },
    %{
      id: "ops-work-items",
      section: "Operations",
      icon: "hero-list-bullet",
      label: "Work Items",
      tooltip: "Individual tasks and deliverables within projects",
      path: "/execution/work-items",
      badge: 0,
      hot: false,
      match: ["/execution/work-items"]
    },
    %{
      id: "ops-tickets",
      section: "Operations",
      icon: "hero-wrench-screwdriver",
      label: "Service tickets",
      tooltip: "Support and service requests from clients — track resolution and billing",
      path: "/execution/service-tickets",
      badge: 0,
      hot: false,
      match: ["/execution/service-tickets"]
    },
    %{
      id: "ops-workorders",
      section: "Operations",
      icon: "hero-calendar-days",
      label: "Work orders",
      tooltip: "Scheduled field work — dispatched jobs with time, location, and crew",
      path: "/execution/work-orders",
      badge: 0,
      hot: false,
      match: ["/execution/work-orders"]
    },

    # Finance
    %{
      id: "fin-dashboard",
      section: "Finance",
      icon: "hero-squares-2x2",
      label: "Dashboard",
      tooltip: "Finance dashboard — overview of revenue, outstanding invoices, payments, and cash position",
      path: "/finance/dashboard",
      badge: 0,
      hot: false,
      match: ["/finance/dashboard"]
    },
    %{
      id: "fin-recurring",
      section: "Finance",
      icon: "hero-arrow-path",
      label: "Recurring",
      tooltip: "Recurring invoice templates — auto-generate invoices on a schedule",
      path: "/finance/recurring-invoices",
      badge: 0,
      hot: false,
      match: ["/finance/recurring-invoices"]
    },
    %{
      id: "fin-time-entries",
      section: "Finance",
      icon: "hero-clock",
      label: "Time Entries",
      tooltip: "Billable hours logged by the team — submit and approve before invoicing",
      path: "/finance/time-entries",
      badge: 0,
      hot: false,
      match: ["/finance/time-entries"]
    },
    %{
      id: "fin-approval-queue",
      section: "Finance",
      icon: "hero-check-circle",
      label: "Approvals",
      tooltip: "Time entries waiting for manager approval before they can be billed",
      path: "/finance/time-entries/approval-queue",
      badge: 0,
      hot: false,
      match: ["/finance/time-entries/approval-queue"]
    },
    %{
      id: "fin-invoices",
      section: "Finance",
      icon: "hero-document-text",
      label: "Invoices",
      tooltip: "Client invoices — create, issue, track payments, and export",
      path: "/finance/invoices",
      badge: 0,
      hot: false,
      match: ["/finance/invoices"]
    },
    %{
      id: "fin-payments",
      section: "Finance",
      icon: "hero-credit-card",
      label: "Payments",
      tooltip: "Payments received from clients — record and apply to outstanding invoices",
      path: "/finance/payments",
      badge: 0,
      hot: false,
      match: ["/finance/payments", "/finance/payment-applications"]
    },
    %{
      id: "fin-expenses",
      section: "Finance",
      icon: "hero-receipt-percent",
      label: "Expenses",
      tooltip: "Non-labor costs — travel, materials, equipment, software and other expenses",
      path: "/finance/expenses",
      badge: 0,
      hot: false,
      match: ["/finance/expenses"]
    },
    %{
      id: "fin-ar-aging",
      section: "Finance",
      icon: "hero-clock",
      label: "AR Aging",
      tooltip: "Accounts receivable aging — outstanding invoices grouped by how overdue they are (Current, 1–30, 31–60, 61–90, 90+ days)",
      path: "/finance/ar-aging",
      badge: 0,
      hot: false,
      match: ["/finance/ar-aging"]
    },
    %{
      id: "fin-credit-notes",
      section: "Finance",
      icon: "hero-minus-circle",
      label: "Credit Notes",
      tooltip: "Credit notes issued to clients — auto-generated when an invoice is voided",
      path: "/finance/credit-notes",
      badge: 0,
      hot: false,
      match: ["/finance/credit-notes"]
    },
    %{
      id: "fin-mercury",
      section: "Finance",
      icon: "hero-building-library",
      label: "Mercury",
      tooltip: "Mercury bank — live account balances, incoming transactions, and payment matching",
      path: "/finance/mercury",
      badge: 0,
      hot: false,
      match: ["/finance/mercury"]
    },
    %{
      id: "fin-mercury-aliases",
      section: "Finance",
      icon: "hero-tag",
      label: "Bank Aliases",
      tooltip: "Bank aliases — map counterparty names from Mercury transactions to client organizations for automatic payment matching",
      path: "/finance/mercury/aliases",
      badge: 0,
      hot: false,
      match: ["/finance/mercury/aliases"]
    },
    %{
      id: "fin-bank-rules",
      section: "Finance",
      icon: "hero-funnel",
      label: "Bank Rules",
      tooltip: "Bank rules — auto-categorize Mercury transactions based on counterparty name, direction, and amount",
      path: "/finance/bank-rules",
      badge: 0,
      hot: false,
      match: ["/finance/bank-rules"]
    },
    %{
      id: "fin-chart-of-accounts",
      section: "Finance",
      icon: "hero-list-bullet",
      label: "Chart of Accounts",
      tooltip: "Master list of GL accounts — add and manage the accounts used for double-entry bookkeeping",
      path: "/finance/chart-of-accounts",
      badge: 0,
      hot: false,
      match: ["/finance/chart-of-accounts"]
    },
    %{
      id: "fin-journal-entries",
      section: "Finance",
      icon: "hero-book-open",
      label: "Journal Entries",
      tooltip: "Double-entry journal entries — auto-posted from invoices, payments, expenses, and manual entries",
      path: "/finance/journal-entries",
      badge: 0,
      hot: false,
      match: ["/finance/journal-entries"]
    },
    %{
      id: "fin-report-pl",
      section: "Finance",
      icon: "hero-chart-bar",
      label: "Profit & Loss",
      tooltip: "Revenue and expense summary for any date range",
      path: "/finance/reports/profit-loss",
      badge: 0,
      hot: false,
      match: ["/finance/reports/profit-loss"]
    },
    %{
      id: "fin-report-bs",
      section: "Finance",
      icon: "hero-chart-bar",
      label: "Balance Sheet",
      tooltip: "Assets, liabilities, and equity as of any date",
      path: "/finance/reports/balance-sheet",
      badge: 0,
      hot: false,
      match: ["/finance/reports/balance-sheet"]
    },
    %{
      id: "fin-report-gl",
      section: "Finance",
      icon: "hero-magnifying-glass",
      label: "GL Detail",
      tooltip: "Transaction detail for any account within a date range",
      path: "/finance/reports/gl-detail",
      badge: 0,
      hot: false,
      match: ["/finance/reports/gl-detail"]
    },
    %{
      id: "fin-billing-reminders",
      section: "Finance",
      icon: "hero-bell",
      label: "Billing Reminders",
      tooltip: "Configure automatic payment reminder emails — set how many days after due date to remind clients",
      path: "/finance/settings",
      badge: 0,
      hot: false,
      match: ["/finance/settings"]
    },

    # Settings
    %{
      id: "set-agents",
      section: "Settings",
      icon: "hero-cpu-chip",
      label: "Agents",
      tooltip: "Autonomous AI agents — configure, monitor, and manage agent tasks",
      path: "/console/agents",
      badge: 0,
      hot: false,
      match: ["/console/agents"]
    },
    %{
      id: "set-users",
      section: "Settings",
      icon: "hero-users",
      label: "Users",
      tooltip: "User accounts — manage staff access and permissions",
      path: "/settings/users",
      badge: 0,
      hot: false,
      match: ["/settings/users"]
    }
  ]

  # ---------------------------------------------------------------------------
  # Helpers (also exported for layouts/LiveViews)
  # ---------------------------------------------------------------------------

  def destinations, do: @destinations
  def rail_areas, do: @rail_areas
  def bottom_areas, do: @bottom_areas

  def area_dests(area_id), do: Enum.filter(@destinations, &(&1.section == area_id))

  def area_has_hot?(area_id),
    do: Enum.any?(@destinations, &(&1.section == area_id and &1.hot))

  def area_for_path(path) when is_binary(path) do
    cond do
      path == "/" -> "Workspace"
      String.starts_with?(path, "/agent") -> "Workspace"
      String.starts_with?(path, "/acquisition") -> "Acquisition"
      String.starts_with?(path, "/procurement") -> "Procurement"
      String.starts_with?(path, "/commercial") -> "Commercial"
      String.starts_with?(path, "/operations") -> "Operations"
      String.starts_with?(path, "/execution") -> "Operations"
      String.starts_with?(path, "/finance") -> "Finance"
      String.starts_with?(path, "/console") -> "Settings"
      String.starts_with?(path, "/settings") -> "Settings"
      true -> "Workspace"
    end
  end

  def area_for_path(_), do: "Workspace"

  def active_dest(path, area) do
    area_dests(area)
    |> Enum.filter(&path_matches?(&1, path))
    |> Enum.max_by(&match_specificity(&1, path), fn -> nil end)
    |> case do
      nil -> List.first(area_dests(area))
      d -> d
    end
  end

  defp match_specificity(%{match: matches}, path) when is_list(matches) and matches != [] do
    matches
    |> Enum.filter(fn m -> path == m or String.starts_with?(path, m <> "/") end)
    |> Enum.map(&String.length/1)
    |> Enum.max(fn -> 0 end)
  end

  defp match_specificity(%{path: dest_path}, _path), do: String.length(dest_path)

  defp path_matches?(%{match: matches}, path) when is_list(matches) and matches != [] do
    Enum.any?(matches, fn m -> path == m or String.starts_with?(path, m <> "/") end)
  end

  defp path_matches?(%{path: dest_path}, path) do
    path == dest_path or String.starts_with?(path, dest_path <> "/")
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  @doc "Two-stroke leaf brand mark."
  attr :class, :string, default: "size-5"

  def leaf_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
    >
      <path d="M5 19c0-7 5-13 14-14-1 9-7 14-14 14z" />
      <path d="M5 19l9-9" />
    </svg>
    """
  end

  attr :area, :string, required: true

  def rail(assigns) do
    ~H"""
    <div class="flex w-14 flex-col items-center gap-1 border-r border-base-content/10 bg-base-200 py-3">
      <.link
        navigate="/"
        class="mb-2 flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-content"
      >
        <.leaf_icon class="size-5" />
      </.link>

      <div :for={a <- rail_areas()} class="relative">
        <.link
          navigate={first_path_in_area(a.id)}
          title={a.label}
          class={[
            "flex h-10 w-10 items-center justify-center rounded-lg border transition",
            @area == a.id && "border-primary/30 bg-primary/10 text-primary",
            @area != a.id && "border-transparent text-base-content/60 hover:bg-base-300"
          ]}
        >
          <.icon name={a.icon} class="size-5" />
        </.link>

        <span
          :if={area_has_hot?(a.id)}
          class="pointer-events-none absolute top-1 right-1 size-1.5 rounded-full bg-error"
        />
      </div>

      <div class="flex-1" />

      <button
        type="button"
        class="flex h-10 w-10 items-center justify-center rounded-lg text-base-content/60 hover:bg-base-300"
        title="Search"
      >
        <.icon name="hero-magnifying-glass" class="size-5" />
      </button>
    </div>
    """
  end

  attr :area, :string, required: true
  attr :open_count, :integer, required: true
  slot :extra

  def area_header(assigns) do
    ~H"""
    <div class="border-b border-base-content/10 bg-base-200">
      <div class="flex min-h-[44px] items-center gap-2.5 px-4 py-1.5">
        <span class="text-[9px] font-semibold tracking-[0.18em] text-base-content/40">AREA</span>
        <span class="text-[13px] font-semibold">{@area}</span>
        <span class="text-[11px] text-base-content/40">· {@open_count} open</span>

        <div class="flex-1" />

        <div class="flex items-center gap-2">
          {render_slot(@extra)}
        </div>
      </div>
    </div>
    """
  end

  attr :area, :string, required: true
  attr :active_id, :string, required: true

  def tab_strip(assigns) do
    ~H"""
    <div id="tab-strip" phx-hook="TabStripScroll" class="flex items-end gap-0.5 border-b border-base-content/10 bg-base-200 px-2 overflow-x-auto">
      <.link
        :for={d <- area_dests(@area)}
        navigate={d.path}
        title={Map.get(d, :tooltip, d.label)}
        class={[
          "group relative top-px flex h-8 shrink-0 items-center gap-2 rounded-t-lg pl-3 pr-2.5 text-[12px] transition",
          @active_id == d.id &&
            "z-10 border border-b-0 border-base-content/10 bg-base-100 font-semibold",
          @active_id != d.id &&
            "border border-b-0 border-transparent font-medium text-base-content/60 hover:bg-base-300"
        ]}
      >
        <.icon name={d.icon} class="size-3.5 shrink-0" />
        <span class="whitespace-nowrap text-left">{d.label}</span>
        <span
          :if={d.badge > 0}
          class={[
            "rounded-full px-1.5 py-px text-[9px] font-semibold",
            d.hot && "bg-error text-error-content",
            !d.hot && "bg-base-300 text-base-content/60"
          ]}
        >
          {d.badge}
        </span>
      </.link>
    </div>
    """
  end

  attr :area, :string, required: true
  attr :active_label, :string, required: true
  slot :actions

  def mobile_top(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 border-b border-base-content/10 bg-base-200 px-4 py-2.5 lg:hidden">
      <.link
        navigate="/"
        class="flex h-7 w-7 items-center justify-center rounded-md bg-primary text-primary-content"
      >
        <.leaf_icon class="size-4" />
      </.link>
      <div class="flex-1 min-w-0">
        <div class="text-[9px] font-semibold tracking-[0.13em] text-primary">
          {String.upcase(@area)}
        </div>
        <div class="truncate text-sm font-semibold">{@active_label}</div>
      </div>
      {render_slot(@actions)}
    </div>
    """
  end

  attr :area, :string, required: true

  def mobile_bar(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-40 flex items-stretch border-t border-base-content/10 bg-base-200 px-1 pb-6 pt-1.5 lg:hidden">
      <button
        :for={a <- bottom_areas()}
        type="button"
        phx-click={toggle_sheet(a.id)}
        class={[
          "relative flex flex-1 flex-col items-center justify-center gap-0.5 rounded-lg py-1.5",
          a.id == @area && "text-primary",
          a.id != @area && "text-base-content/60"
        ]}
      >
        <div class="relative">
          <.icon name={a.icon} class="size-5" />
          <span
            :if={a.id != "more" and area_has_hot?(a.id)}
            class="absolute -right-1 -top-0.5 size-2 rounded-full border-2 border-base-200 bg-error"
          />
        </div>
        <div class={[
          "text-[10px]",
          a.id == @area && "font-semibold",
          a.id != @area && "font-medium"
        ]}>
          {a.label}
        </div>
      </button>
    </div>

    <%!-- Backdrop (hidden by default; toggle_sheet shows it) --%>
    <div
      id="mobile-sheet-backdrop"
      class="hidden fixed inset-0 z-40 bg-base-100/80 backdrop-blur-sm lg:hidden"
      phx-click={hide_sheets()}
    />

    <%!-- One sheet per area, hidden by default --%>
    <.mobile_sheet :for={a <- bottom_areas()} area_id={a.id} />
    """
  end

  attr :area_id, :string, required: true

  def mobile_sheet(assigns) do
    items =
      case assigns.area_id do
        "more" ->
          for area <- ["Reports", "Settings", "Workspace"], d <- area_dests(area), do: d

        id ->
          area_dests(id)
      end

    title =
      case assigns.area_id do
        "more" -> "More"
        id -> id
      end

    assigns = assigns |> assign(:items, items) |> assign(:title, title)

    ~H"""
    <div
      id={"mobile-sheet-#{@area_id}"}
      class="hidden fixed bottom-20 left-2 right-2 z-50 overflow-hidden rounded-2xl border border-base-content/10 bg-base-200 shadow-2xl lg:hidden"
    >
      <div class="flex items-center gap-2.5 border-b border-base-content/10 px-4 py-3">
        <span class="text-[9px] font-semibold tracking-[0.13em] text-base-content/40">AREA</span>
        <span class="text-sm font-semibold">{@title}</span>
        <span class="text-[11px] text-base-content/40">· {length(@items)} windows</span>
      </div>
      <div class="max-h-[360px] overflow-y-auto p-1.5">
        <.link
          :for={d <- @items}
          navigate={d.path}
          phx-click={hide_sheets()}
          class="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left hover:bg-base-300"
        >
          <div class="flex h-8 w-8 items-center justify-center rounded-md bg-base-300 text-base-content/60">
            <.icon name={d.icon} class="size-4" />
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-[13px] font-medium">{d.label}</div>
            <div :if={@area_id == "more"} class="mt-0.5 text-[10px] text-base-content/40">
              {d.section}
            </div>
          </div>
          <span
            :if={d.badge > 0}
            class={[
              "rounded-full px-2 py-0.5 text-[10px] font-semibold",
              d.hot && "bg-error text-error-content",
              !d.hot && "bg-base-300 text-base-content/60"
            ]}
          >
            {d.badge}
          </span>
        </.link>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp first_path_in_area(area_id) do
    case List.first(area_dests(area_id)) do
      nil -> "/"
      d -> d.path
    end
  end

  defp toggle_sheet(area_id) do
    JS.remove_class("hidden", to: "#mobile-sheet-backdrop")
    |> JS.remove_class("hidden", to: "#mobile-sheet-#{area_id}")
  end

  defp hide_sheets do
    JS.add_class("hidden", to: "#mobile-sheet-backdrop")
    |> JS.add_class("hidden", to: "##{"mobile-sheet-Acquisition"}")
    |> JS.add_class("hidden", to: "##{"mobile-sheet-Procurement"}")
    |> JS.add_class("hidden", to: "##{"mobile-sheet-Commercial"}")
    |> JS.add_class("hidden", to: "##{"mobile-sheet-Operations"}")
    |> JS.add_class("hidden", to: "##{"mobile-sheet-Finance"}")
    |> JS.add_class("hidden", to: "##{"mobile-sheet-more"}")
  end
end
