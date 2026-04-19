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
      "flex grow flex-col bg-emerald-800 dark:bg-emerald-950",
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
      <nav class="flex flex-1 flex-col overflow-y-auto">
        <ul role="list" class="-mx-2 flex flex-1 flex-col gap-y-1">
          <%!-- Signal inbox (always visible, top-level) --%>
          <.nav_item
            path={~p"/commercial/signals"}
            current_path={@current_path}
            icon="hero-inbox-stack"
            collapsed={@collapsed}
            badge={@nav_counts[:signals]}
          >
            Signal Inbox
          </.nav_item>

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
            <.nav_item
              path={~p"/operations/managed-systems"}
              current_path={@current_path}
              icon="hero-circle-stack"
              collapsed={@collapsed}
            >
              Managed Systems
            </.nav_item>
            <.nav_item
              path={~p"/operations/affiliations"}
              current_path={@current_path}
              icon="hero-link"
              collapsed={@collapsed}
            >
              Affiliations
            </.nav_item>
            <.nav_item
              path={~p"/operations/assets"}
              current_path={@current_path}
              icon="hero-cpu-chip"
              collapsed={@collapsed}
            >
              Assets
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
              Signals
            </.nav_item>
            <.nav_item
              path={~p"/commercial/discovery-programs"}
              current_path={@current_path}
              icon="hero-radar"
              collapsed={@collapsed}
            >
              Discovery Programs
            </.nav_item>
            <.nav_item
              path={~p"/commercial/targets"}
              current_path={@current_path}
              icon="hero-magnifying-glass"
              collapsed={@collapsed}
              badge={@nav_counts[:targets]}
            >
              Targets
            </.nav_item>
            <.nav_item
              path={~p"/commercial/observations"}
              current_path={@current_path}
              icon="hero-document-magnifying-glass"
              collapsed={@collapsed}
            >
              Observations
            </.nav_item>
            <.nav_item
              path={~p"/commercial/pursuits"}
              current_path={@current_path}
              icon="hero-rocket-launch"
              collapsed={@collapsed}
            >
              Pursuits
            </.nav_item>
            <.nav_item
              path={~p"/commercial/proposals"}
              current_path={@current_path}
              icon="hero-document-text"
              collapsed={@collapsed}
            >
              Proposals
            </.nav_item>
            <.nav_item
              path={~p"/commercial/agreements"}
              current_path={@current_path}
              icon="hero-document-check"
              collapsed={@collapsed}
            >
              Agreements
            </.nav_item>
            <.nav_item
              path={~p"/commercial/change-orders"}
              current_path={@current_path}
              icon="hero-arrow-path"
              collapsed={@collapsed}
            >
              Change Orders
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
              path={~p"/execution/work-items"}
              current_path={@current_path}
              icon="hero-queue-list"
              collapsed={@collapsed}
            >
              Work Items
            </.nav_item>
            <.nav_item
              path={~p"/execution/assignments"}
              current_path={@current_path}
              icon="hero-calendar-days"
              collapsed={@collapsed}
            >
              Assignments
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
            <.nav_item
              path={~p"/finance/payment-applications"}
              current_path={@current_path}
              icon="hero-link"
              collapsed={@collapsed}
            >
              Applications
            </.nav_item>
          </.nav_group>

          <%!-- Agents section --%>
          <.nav_group
            id={"#{@id}-agents"}
            label="Agents"
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
              Console
            </.nav_item>
            <.nav_item
              path={~p"/procurement/bids"}
              current_path={@current_path}
              icon="hero-document-text"
              collapsed={@collapsed}
              badge={@nav_counts[:bids]}
            >
              Bids
            </.nav_item>
            <.nav_item
              path={~p"/procurement/sources"}
              current_path={@current_path}
              icon="hero-globe-alt"
              collapsed={@collapsed}
            >
              Procurement Sources
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

        <%!-- User + theme toggle --%>
        <%= if @current_user do %>
          <div class={[
            "flex items-center py-3 text-sm/6 font-semibold text-white",
            if(@collapsed, do: "flex-col gap-2 px-3", else: "gap-x-3 px-4")
          ]}>
            <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-xs font-medium text-white ring-1 ring-white/20">
              {String.first(@current_user.email || "U") |> String.upcase()}
            </span>
            <span :if={!@collapsed} class="flex-1 truncate text-sm">{@current_user.email}</span>
            <div class="flex items-center gap-1">
              <.sidebar_theme_toggle />
              <.link
                :if={!@collapsed}
                href={~p"/sign-out"}
                method="delete"
                class="text-emerald-300 hover:text-white"
                title="Sign out"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
              </.link>
            </div>
          </div>
        <% else %>
          <div class={[
            "flex items-center py-3 text-sm/6 font-semibold text-white",
            if(@collapsed, do: "flex-col gap-2 px-3", else: "gap-x-3 px-4")
          ]}>
            <.link
              href={~p"/sign-in"}
              class="flex items-center gap-x-2 text-white hover:text-emerald-200"
            >
              <.icon name="hero-arrow-left-on-rectangle" class="size-5" />
              <span :if={!@collapsed}>Sign in</span>
            </.link>
            <div :if={!@collapsed} class="ml-auto">
              <.sidebar_theme_toggle />
            </div>
            <div :if={@collapsed}>
              <.sidebar_theme_toggle />
            </div>
          </div>
        <% end %>
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

  # -- Theme toggle --

  defp sidebar_theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 rounded-full bg-emerald-900/50 p-0.5 ring-1 ring-inset ring-emerald-600/30">
      <button
        class="flex size-6 items-center justify-center rounded-full transition [[data-theme=light]_&]:bg-emerald-600 [[data-theme=light]_&]:shadow-sm"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light"
      >
        <.icon
          name="hero-sun-micro"
          class="size-3.5 text-emerald-400 [[data-theme=light]_&]:text-white"
        />
      </button>
      <button
        class="flex size-6 items-center justify-center rounded-full transition dark:[[data-theme=dark]_&]:bg-emerald-600"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark"
      >
        <.icon
          name="hero-moon-micro"
          class="size-3.5 text-emerald-400 dark:[[data-theme=dark]_&]:text-white"
        />
      </button>
      <button
        class="flex size-6 items-center justify-center rounded-full transition [[data-theme=system]_&]:bg-emerald-600 [[data-theme=system]_&]:shadow-sm dark:[[data-theme=system]_&]:bg-emerald-600"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System"
      >
        <.icon
          name="hero-computer-desktop-micro"
          class="size-3.5 text-emerald-400 [[data-theme=system]_&]:text-white dark:[[data-theme=system]_&]:text-white"
        />
      </button>
    </div>
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

  defp is_active?(current_path, path) do
    current_path == path or
      (path != "/" and String.starts_with?(current_path, path))
  end
end
