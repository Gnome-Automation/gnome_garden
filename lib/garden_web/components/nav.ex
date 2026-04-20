defmodule GnomeGardenWeb.Nav do
  @moduledoc """
  Garden-themed sidebar navigation with collapsible sections.
  """
  use Phoenix.Component
  use GnomeGardenWeb, :verified_routes

  import GnomeGardenWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, default: "nav"
  attr :current_path, :string, default: "/"
  attr :current_user, :map, default: nil
  attr :collapsed, :boolean, default: false
  attr :nav_counts, :map, default: %{}

  def sidebar_nav(assigns) do
    ~H"""
    <div class={[
      "flex h-full min-h-0 grow flex-col bg-emerald-800 dark:bg-emerald-950",
      if(@collapsed, do: "px-3", else: "px-6")
    ]}>
      <%!-- Logo --%>
      <div class="flex h-16 shrink-0 items-center">
        <a href="/" class="flex items-center gap-2">
          <img src={~p"/images/logo.svg"} class="h-8 w-auto rounded" />
          <span :if={!@collapsed} class="text-lg font-bold text-white">Gnome Garden</span>
        </a>
      </div>

      <%!-- Scrollable nav --%>
      <nav class="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <ul role="list" class="-mx-2 flex flex-1 flex-col gap-y-1">
          <%!-- Home --%>
          <.nav_item
            path={~p"/"}
            current_path={@current_path}
            icon="hero-home"
            collapsed={@collapsed}
          >
            Home
          </.nav_item>

          <%!-- Acquisition section --%>
          <.nav_group
            id={"#{@id}-acquisition"}
            label="Acquisition"
            icon="hero-inbox-stack"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/acquisition/findings"}
              current_path={@current_path}
              icon="hero-inbox-stack"
              collapsed={@collapsed}
              badge={@nav_counts[:findings]}
            >
              Queue
            </.nav_item>
            <.nav_item
              path={~p"/acquisition/sources"}
              current_path={@current_path}
              icon="hero-globe-alt"
              collapsed={@collapsed}
            >
              Sources
            </.nav_item>
            <.nav_item
              path={~p"/acquisition/programs"}
              current_path={@current_path}
              icon="hero-radar"
              collapsed={@collapsed}
            >
              Programs
            </.nav_item>
          </.nav_group>

          <%!-- Procurement section --%>
          <.nav_group
            id={"#{@id}-procurement"}
            label="Procurement"
            icon="hero-briefcase"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/procurement/targeting"}
              current_path={@current_path}
              icon="hero-funnel"
              collapsed={@collapsed}
            >
              Targeting
            </.nav_item>
          </.nav_group>

          <%!-- Commercial section --%>
          <.nav_group
            id={"#{@id}-commercial"}
            label="Commercial"
            icon="hero-arrow-trending-up"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/commercial/signals"}
              current_path={@current_path}
              icon="hero-inbox-stack"
              collapsed={@collapsed}
              badge={@nav_counts[:signals]}
            >
              Signal Queue
            </.nav_item>
            <.nav_item
              path={~p"/commercial/discovery-programs"}
              current_path={@current_path}
              icon="hero-radar"
              collapsed={@collapsed}
            >
              Programs
            </.nav_item>
            <.nav_item
              path={~p"/commercial/pursuits"}
              current_path={@current_path}
              icon="hero-rocket-launch"
              collapsed={@collapsed}
            >
              Pursuits
            </.nav_item>
          </.nav_group>

          <%!-- Operations section --%>
          <.nav_group
            id={"#{@id}-operations"}
            label="Operations"
            icon="hero-building-office-2"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/operations/organizations"}
              current_path={@current_path}
              icon="hero-building-office-2"
              collapsed={@collapsed}
            >
              Organizations
            </.nav_item>
            <.nav_item
              path={~p"/operations/people"}
              current_path={@current_path}
              icon="hero-users"
              collapsed={@collapsed}
            >
              People
            </.nav_item>
            <.nav_item
              path={~p"/operations/sites"}
              current_path={@current_path}
              icon="hero-map-pin"
              collapsed={@collapsed}
            >
              Sites
            </.nav_item>
          </.nav_group>

          <%!-- Execution section --%>
          <.nav_group
            id={"#{@id}-execution"}
            label="Execution"
            icon="hero-wrench-screwdriver"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/execution/projects"}
              current_path={@current_path}
              icon="hero-wrench-screwdriver"
              collapsed={@collapsed}
            >
              Projects
            </.nav_item>
            <.nav_item
              path={~p"/execution/service-tickets"}
              current_path={@current_path}
              icon="hero-lifebuoy"
              collapsed={@collapsed}
            >
              Service Tickets
            </.nav_item>
            <.nav_item
              path={~p"/execution/work-orders"}
              current_path={@current_path}
              icon="hero-wrench-screwdriver"
              collapsed={@collapsed}
            >
              Work Orders
            </.nav_item>
            <.nav_item
              path={~p"/execution/maintenance-plans"}
              current_path={@current_path}
              icon="hero-arrow-path"
              collapsed={@collapsed}
            >
              Maintenance Plans
            </.nav_item>
          </.nav_group>

          <%!-- Finance section --%>
          <.nav_group
            id={"#{@id}-finance"}
            label="Finance"
            icon="hero-receipt-percent"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/finance/invoices"}
              current_path={@current_path}
              icon="hero-receipt-percent"
              collapsed={@collapsed}
            >
              Invoices
            </.nav_item>
            <.nav_item
              path={~p"/finance/time-entries"}
              current_path={@current_path}
              icon="hero-clock"
              collapsed={@collapsed}
            >
              Time Entries
            </.nav_item>
            <.nav_item
              path={~p"/finance/expenses"}
              current_path={@current_path}
              icon="hero-credit-card"
              collapsed={@collapsed}
            >
              Expenses
            </.nav_item>
            <.nav_item
              path={~p"/finance/payments"}
              current_path={@current_path}
              icon="hero-banknotes"
              collapsed={@collapsed}
            >
              Payments
            </.nav_item>
          </.nav_group>

          <%!-- Console section --%>
          <.nav_group
            id={"#{@id}-console"}
            label="Console"
            icon="hero-cpu-chip"
            collapsed={@collapsed}
            current_path={@current_path}
          >
            <.nav_item
              path={~p"/console/agents"}
              current_path={@current_path}
              icon="hero-cpu-chip"
              collapsed={@collapsed}
            >
              Agents
            </.nav_item>
            <.nav_item
              path={~p"/agent"}
              current_path={@current_path}
              icon="hero-command-line"
              collapsed={@collapsed}
            >
              Workbench
            </.nav_item>
          </.nav_group>
        </ul>
      </nav>

      <%!-- Pinned bottom --%>
      <div class="shrink-0 border-t border-emerald-700 dark:border-emerald-900">
        <%!-- Collapse toggle (desktop only) --%>
        <div class="hidden lg:block px-1 pt-2">
          <button
            phx-click={toggle_sidebar()}
            class={[
              "flex w-full items-center rounded-md p-2 text-sm text-emerald-300 hover:bg-emerald-700 hover:text-white transition",
              if(@collapsed, do: "justify-center", else: "gap-x-3")
            ]}
            title={if(@collapsed, do: "Expand sidebar", else: "Collapse sidebar")}
          >
            <.icon
              name={if(@collapsed, do: "hero-chevron-right", else: "hero-chevron-left")}
              class="size-5 shrink-0"
            />
            <span :if={!@collapsed} class="truncate">Collapse</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :current_path, :string, default: "/"
  attr :nav_counts, :map, default: %{}

  def section_subnav(assigns) do
    section = current_section(assigns.current_path)
    items = section_subnav_items(section)

    assigns =
      assigns
      |> assign(:section, section)
      |> assign(:items, items)

    ~H"""
    <div :if={@items != []} class="flex flex-wrap items-center gap-2">
      <span class="shrink-0 text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400 dark:text-zinc-500">
        {section_label(@section)}
      </span>
      <.subnav_link
        :for={item <- @items}
        path={item.path}
        label={item.label}
        icon={item.icon}
        current_path={@current_path}
        badge={subnav_badge(Map.get(item, :badge_key), @nav_counts)}
      />
    </div>
    """
  end

  attr :current_path, :string, default: "/"
  attr :page_title, :string, default: nil

  def section_context(assigns) do
    context = section_context_data(assigns.current_path, assigns.page_title)
    assigns = assign(assigns, :context, context)

    ~H"""
    <div :if={@context} class="flex flex-wrap items-center gap-3 text-sm">
      <.link
        navigate={@context.back_path}
        class="inline-flex items-center gap-2 rounded-full border border-zinc-200 bg-white px-3 py-1.5 font-medium text-zinc-600 transition hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-zinc-900/80 dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
      >
        <.icon name="hero-arrow-left" class="size-4" />
        <span>{@context.back_label}</span>
      </.link>

      <span class="text-zinc-300 dark:text-zinc-600">/</span>

      <div class="min-w-0">
        <p class="truncate font-medium text-zinc-900 dark:text-white">{@context.current_label}</p>
      </div>
    </div>
    """
  end

  attr :current_path, :string, default: "/"
  attr :nav_counts, :map, default: %{}

  def mobile_primary_nav(assigns) do
    ~H"""
    <div class="fixed inset-x-0 bottom-0 z-40 border-t border-zinc-200 bg-white/95 px-2 py-2 shadow-[0_-8px_24px_rgba(15,23,42,0.08)] backdrop-blur lg:hidden dark:border-white/10 dark:bg-zinc-900/95">
      <div class="grid grid-cols-5 gap-1">
        <.mobile_tab path={~p"/"} current_path={@current_path} icon="hero-home" label="Home" />
        <.mobile_tab
          path={~p"/acquisition/findings"}
          current_path={@current_path}
          icon="hero-inbox-stack"
          label="Intake"
          badge={subnav_badge(:findings, @nav_counts)}
        />
        <.mobile_tab
          path={~p"/commercial/signals"}
          current_path={@current_path}
          icon="hero-inbox-stack"
          label="Signals"
          badge={subnav_badge(:signals, @nav_counts)}
        />
        <.mobile_tab
          path={~p"/commercial/pursuits"}
          current_path={@current_path}
          icon="hero-rocket-launch"
          label="Pursuits"
        />
        <button
          type="button"
          phx-click={
            JS.remove_class("hidden", to: "#mobile-sidebar-backdrop")
            |> JS.remove_class("-translate-x-full", to: "#mobile-sidebar")
            |> JS.add_class("translate-x-0", to: "#mobile-sidebar")
            |> JS.focus_first(to: "#mobile-sidebar")
          }
          class="flex flex-col items-center justify-center rounded-2xl px-2 py-2 text-[11px] font-medium text-zinc-500 transition hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/[0.05] dark:hover:text-white"
        >
          <.icon name="hero-ellipsis-horizontal-circle" class="size-5" />
          <span class="mt-1">More</span>
        </button>
      </div>
    </div>
    """
  end

  # -- Collapsible nav group --

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :collapsed, :boolean, default: false
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  defp nav_group(assigns) do
    ~H"""
    <li :if={!@collapsed} class="mt-4">
      <button
        type="button"
        phx-click={
          JS.toggle(to: "##{@id}-items")
          |> JS.toggle_class("rotate-90", to: "##{@id}-chevron")
        }
        class="group flex w-full items-center gap-x-3 rounded-md p-2 text-left text-sm/6 font-semibold text-emerald-200 hover:bg-emerald-700 hover:text-white transition"
      >
        <.icon name={@icon} class="size-5 shrink-0 text-emerald-300 group-hover:text-white" />
        {@label}
        <.icon
          name="hero-chevron-right-mini"
          id={"#{@id}-chevron"}
          class="ml-auto size-5 shrink-0 text-emerald-400 transition-transform duration-150 rotate-90"
        />
      </button>
      <ul id={"#{@id}-items"} role="list" class="mt-1 space-y-1 pl-2">
        {render_slot(@inner_block)}
      </ul>
    </li>
    <%!-- Collapsed: just show a divider, items hidden --%>
    <li :if={@collapsed} class="mt-3">
      <div class="mx-auto h-px w-4 bg-emerald-600 mb-2" />
      {render_slot(@inner_block)}
    </li>
    """
  end

  # -- Nav item --

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :external, :boolean, default: false
  attr :collapsed, :boolean, default: false
  attr :badge, :integer, default: nil
  slot :inner_block, required: true

  defp nav_item(assigns) do
    active = is_active?(assigns.current_path, assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <li>
      <%= if @external do %>
        <.link
          href={@path}
          class={nav_link_classes(@active, @collapsed)}
          title={if(@collapsed, do: render_slot(@inner_block))}
        >
          <.icon name={@icon} class={nav_icon_classes(@active)} />
          <span :if={!@collapsed} class="truncate">{render_slot(@inner_block)}</span>
          <.nav_badge
            :if={@badge && @badge > 0}
            count={@badge}
            active={@active}
            collapsed={@collapsed}
          />
        </.link>
      <% else %>
        <.link
          navigate={@path}
          class={nav_link_classes(@active, @collapsed)}
          title={if(@collapsed, do: render_slot(@inner_block))}
        >
          <.icon name={@icon} class={nav_icon_classes(@active)} />
          <span :if={!@collapsed} class="truncate">{render_slot(@inner_block)}</span>
          <.nav_badge
            :if={@badge && @badge > 0}
            count={@badge}
            active={@active}
            collapsed={@collapsed}
          />
        </.link>
      <% end %>
    </li>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, required: true
  attr :badge, :integer, default: nil

  defp subnav_link(assigns) do
    active = is_active?(assigns.current_path, assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "inline-flex shrink-0 items-center gap-2 rounded-full border px-3 py-2 text-sm font-medium transition",
        if(@active,
          do: "border-emerald-500 bg-emerald-500 text-white shadow-sm shadow-emerald-500/20",
          else:
            "border-zinc-200 bg-white text-zinc-600 hover:border-emerald-300 hover:text-emerald-700 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300 dark:hover:border-emerald-400/40 dark:hover:text-emerald-300"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
      <span>{@label}</span>
      <span
        :if={@badge && @badge > 0}
        class={[
          "rounded-full px-2 py-0.5 text-xs font-semibold",
          if(@active,
            do: "bg-white/20 text-white",
            else: "bg-zinc-100 text-zinc-500 dark:bg-white/10 dark:text-zinc-300"
          )
        ]}
      >
        {if @badge > 99, do: "99+", else: @badge}
      </span>
    </.link>
    """
  end

  attr :path, :string, required: true
  attr :current_path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :badge, :integer, default: nil

  defp mobile_tab(assigns) do
    active = is_active?(assigns.current_path, assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "relative flex flex-col items-center justify-center rounded-2xl px-2 py-2 text-[11px] font-medium transition",
        if(@active,
          do: "bg-emerald-500 text-white shadow-sm shadow-emerald-500/20",
          else:
            "text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/[0.05] dark:hover:text-white"
        )
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span class="mt-1">{@label}</span>
      <span
        :if={@badge && @badge > 0}
        class="absolute right-2 top-1 flex min-w-4 items-center justify-center rounded-full bg-rose-500 px-1 text-[9px] font-bold text-white"
      >
        {if @badge > 9, do: "9+", else: @badge}
      </span>
    </.link>
    """
  end

  attr :count, :integer, required: true
  attr :active, :boolean, default: false
  attr :collapsed, :boolean, default: false

  defp nav_badge(assigns) do
    ~H"""
    <span
      :if={!@collapsed}
      class={[
        "ml-auto w-9 min-w-max rounded-full px-2.5 py-0.5 text-center text-xs/5 font-medium whitespace-nowrap",
        if(@active,
          do: "bg-emerald-600 text-white outline-1 -outline-offset-1 outline-emerald-500",
          else:
            "bg-emerald-900/40 text-emerald-200 outline-1 -outline-offset-1 outline-emerald-700/50"
        )
      ]}
    >
      {if @count > 99, do: "99+", else: @count}
    </span>
    <span
      :if={@collapsed}
      class="absolute -top-1 -right-1 flex size-4 items-center justify-center rounded-full bg-red-500 text-[0.5rem] font-bold text-white"
    >
      {if @count > 9, do: "9+", else: @count}
    </span>
    """
  end

  # -- Helpers --

  defp nav_link_classes(active, collapsed) do
    [
      "group relative flex rounded-md p-2 text-sm/6 font-semibold transition",
      if(collapsed, do: "justify-center", else: "gap-x-3"),
      if(active,
        do: "bg-emerald-700 text-white dark:bg-emerald-900/60",
        else:
          "text-emerald-200 hover:bg-emerald-700 hover:text-white dark:text-emerald-100 dark:hover:bg-emerald-900/40"
      )
    ]
  end

  defp nav_icon_classes(active) do
    [
      "size-6 shrink-0",
      if(active,
        do: "text-white",
        else: "text-emerald-300 group-hover:text-white dark:text-emerald-200"
      )
    ]
  end

  defp toggle_sidebar do
    JS.dispatch("phx:toggle-sidebar")
  end

  defp current_section("/"), do: :home

  defp current_section(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/acquisition") -> :acquisition
      String.starts_with?(path, "/procurement") -> :procurement
      String.starts_with?(path, "/commercial") -> :commercial
      String.starts_with?(path, "/operations") -> :operations
      String.starts_with?(path, "/execution") -> :execution
      String.starts_with?(path, "/finance") -> :finance
      String.starts_with?(path, "/console") -> :console
      String.starts_with?(path, "/agent") -> :console
      true -> nil
    end
  end

  defp current_section(_path), do: nil

  defp section_label(:procurement), do: "Procurement"
  defp section_label(:acquisition), do: "Acquisition"
  defp section_label(:commercial), do: "Commercial"
  defp section_label(:operations), do: "Operations"
  defp section_label(:execution), do: "Execution"
  defp section_label(:finance), do: "Finance"
  defp section_label(:console), do: "Console"
  defp section_label(_), do: "Workspace"

  defp section_subnav_items(:acquisition) do
    [
      %{
        path: ~p"/acquisition/findings",
        label: "Queue",
        icon: "hero-inbox-stack",
        badge_key: :findings
      },
      %{path: ~p"/acquisition/sources", label: "Sources", icon: "hero-globe-alt"},
      %{path: ~p"/acquisition/programs", label: "Programs", icon: "hero-radar"}
    ]
  end

  defp section_subnav_items(:procurement) do
    [
      %{path: ~p"/procurement/targeting", label: "Targeting", icon: "hero-funnel"}
    ]
  end

  defp section_subnav_items(:commercial) do
    [
      %{
        path: ~p"/commercial/signals",
        label: "Signal Queue",
        icon: "hero-inbox-stack",
        badge_key: :signals
      },
      %{path: ~p"/commercial/discovery-programs", label: "Programs", icon: "hero-radar"},
      %{path: ~p"/commercial/pursuits", label: "Pursuits", icon: "hero-rocket-launch"}
    ]
  end

  defp section_subnav_items(:operations) do
    [
      %{
        path: ~p"/operations/organizations",
        label: "Organizations",
        icon: "hero-building-office-2"
      },
      %{path: ~p"/operations/people", label: "People", icon: "hero-users"},
      %{path: ~p"/operations/sites", label: "Sites", icon: "hero-map-pin"},
      %{path: ~p"/operations/managed-systems", label: "Systems", icon: "hero-circle-stack"}
    ]
  end

  defp section_subnav_items(:execution) do
    [
      %{path: ~p"/execution/projects", label: "Projects", icon: "hero-wrench-screwdriver"},
      %{path: ~p"/execution/service-tickets", label: "Tickets", icon: "hero-lifebuoy"},
      %{path: ~p"/execution/work-orders", label: "Work Orders", icon: "hero-wrench-screwdriver"},
      %{path: ~p"/execution/maintenance-plans", label: "Maintenance", icon: "hero-arrow-path"}
    ]
  end

  defp section_subnav_items(:finance) do
    [
      %{path: ~p"/finance/invoices", label: "Invoices", icon: "hero-receipt-percent"},
      %{path: ~p"/finance/time-entries", label: "Time", icon: "hero-clock"},
      %{path: ~p"/finance/expenses", label: "Expenses", icon: "hero-credit-card"},
      %{path: ~p"/finance/payments", label: "Payments", icon: "hero-banknotes"}
    ]
  end

  defp section_subnav_items(:console) do
    [
      %{path: ~p"/console/agents", label: "Agents", icon: "hero-cpu-chip"},
      %{path: ~p"/agent", label: "Workbench", icon: "hero-command-line"}
    ]
  end

  defp section_subnav_items(_), do: []

  defp subnav_badge(nil, _nav_counts), do: nil
  defp subnav_badge(key, nav_counts), do: Map.get(nav_counts || %{}, key)

  defp section_context_data(path, page_title) when is_binary(path) do
    segments = path |> String.split("/", trim: true)

    case segments do
      [section, resource | _rest] when length(segments) > 2 ->
        back_path = "/" <> Enum.join([section, resource], "/")
        back_label = "Back to " <> resource_label(resource)
        current_label = page_title || context_label_from_segments(segments)

        %{back_path: back_path, back_label: back_label, current_label: current_label}

      _ ->
        nil
    end
  end

  defp section_context_data(_path, _page_title), do: nil

  defp context_label_from_segments(segments) do
    case List.last(segments) do
      "new" -> "New " <> singular_resource_label(Enum.at(segments, 1))
      "edit" -> "Edit " <> singular_resource_label(Enum.at(segments, 1))
      last -> titleize_segment(last)
    end
  end

  defp resource_label("bids"), do: "Bid Records"
  defp resource_label("findings"), do: "Acquisition Queue"
  defp resource_label("programs"), do: "Programs"
  defp resource_label("sources"), do: "Sources"
  defp resource_label("targeting"), do: "Targeting"
  defp resource_label("signals"), do: "Signal Queue"
  defp resource_label("targets"), do: "Discovery Records"
  defp resource_label("discovery-programs"), do: "Discovery Programs"
  defp resource_label("observations"), do: "Evidence"
  defp resource_label("pursuits"), do: "Pursuits"
  defp resource_label("organizations"), do: "Organizations"
  defp resource_label("people"), do: "People"
  defp resource_label("sites"), do: "Sites"
  defp resource_label("managed-systems"), do: "Systems"
  defp resource_label("affiliations"), do: "Affiliations"
  defp resource_label("assets"), do: "Assets"
  defp resource_label("projects"), do: "Projects"
  defp resource_label("work-items"), do: "Work Items"
  defp resource_label("assignments"), do: "Assignments"
  defp resource_label("service-tickets"), do: "Service Tickets"
  defp resource_label("work-orders"), do: "Work Orders"
  defp resource_label("maintenance-plans"), do: "Maintenance"
  defp resource_label("invoices"), do: "Invoices"
  defp resource_label("time-entries"), do: "Time Entries"
  defp resource_label("expenses"), do: "Expenses"
  defp resource_label("payments"), do: "Payments"
  defp resource_label("payment-applications"), do: "Payment Applications"
  defp resource_label("agents"), do: "Agents"
  defp resource_label(resource), do: titleize_segment(resource)

  defp singular_resource_label("bids"), do: "Bid"
  defp singular_resource_label("findings"), do: "Finding"
  defp singular_resource_label("programs"), do: "Program"
  defp singular_resource_label("sources"), do: "Source"
  defp singular_resource_label("signals"), do: "Signal"
  defp singular_resource_label("targets"), do: "Discovery Record"
  defp singular_resource_label("discovery-programs"), do: "Discovery Program"
  defp singular_resource_label("observations"), do: "Evidence"
  defp singular_resource_label("pursuits"), do: "Pursuit"
  defp singular_resource_label("organizations"), do: "Organization"
  defp singular_resource_label("people"), do: "Person"
  defp singular_resource_label("sites"), do: "Site"
  defp singular_resource_label("managed-systems"), do: "System"
  defp singular_resource_label("affiliations"), do: "Affiliation"
  defp singular_resource_label("assets"), do: "Asset"
  defp singular_resource_label("projects"), do: "Project"
  defp singular_resource_label("work-items"), do: "Work Item"
  defp singular_resource_label("assignments"), do: "Assignment"
  defp singular_resource_label("service-tickets"), do: "Service Ticket"
  defp singular_resource_label("work-orders"), do: "Work Order"
  defp singular_resource_label("maintenance-plans"), do: "Maintenance Plan"
  defp singular_resource_label("invoices"), do: "Invoice"
  defp singular_resource_label("time-entries"), do: "Time Entry"
  defp singular_resource_label("expenses"), do: "Expense"
  defp singular_resource_label("payments"), do: "Payment"
  defp singular_resource_label("payment-applications"), do: "Payment Application"
  defp singular_resource_label("agents"), do: "Agent"
  defp singular_resource_label(resource), do: titleize_segment(resource)

  defp titleize_segment(segment) do
    segment
    |> to_string()
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp is_active?(current_path, path) do
    current_path == path or
      (path != "/" and String.starts_with?(current_path, path))
  end
end
