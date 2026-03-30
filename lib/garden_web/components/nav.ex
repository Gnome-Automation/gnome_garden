defmodule GnomeGardenWeb.Nav do
  @moduledoc """
  Navigation component with DaisyUI submenus.
  Used for both mobile drawer and desktop sidebar.
  """
  use Phoenix.Component
  use GnomeGardenWeb, :verified_routes

  import GnomeGardenWeb.CoreComponents, only: [icon: 1]

  attr :current_path, :string, default: "/"

  def sidebar_nav(assigns) do
    ~H"""
    <ul class="menu menu-md gap-1 w-full">
      <li>
        <.link navigate={~p"/"} class={active_class(@current_path, "/")}>
          <.icon name="hero-home" class="size-5" />
          <span>Dashboard</span>
        </.link>
      </li>

      <%!-- CRM Submenu --%>
      <li>
        <details open={String.starts_with?(@current_path, "/crm")}>
          <summary class="font-medium">
            <.icon name="hero-briefcase" class="size-5" />
            CRM
          </summary>
          <ul>
            <li>
              <.link navigate={~p"/crm/companies"} class={active_class(@current_path, "/crm/companies")}>
                <.icon name="hero-building-office-2" class="size-4" />
                Companies
              </.link>
            </li>
            <li>
              <.link navigate={~p"/crm/contacts"} class={active_class(@current_path, "/crm/contacts")}>
                <.icon name="hero-users" class="size-4" />
                Contacts
              </.link>
            </li>
            <li>
              <.link navigate={~p"/crm/opportunities"} class={active_class(@current_path, "/crm/opportunities")}>
                <.icon name="hero-currency-dollar" class="size-4" />
                Opportunities
              </.link>
            </li>
            <li>
              <.link navigate={~p"/crm/leads"} class={active_class(@current_path, "/crm/leads")}>
                <.icon name="hero-user-plus" class="size-4" />
                Leads
              </.link>
            </li>
            <li>
              <.link navigate={~p"/crm/tasks"} class={active_class(@current_path, "/crm/tasks")}>
                <.icon name="hero-clipboard-document-check" class="size-4" />
                Tasks
              </.link>
            </li>
          </ul>
        </details>
      </li>

      <%!-- Agents Submenu --%>
      <li>
        <details open={String.starts_with?(@current_path, "/agents")}>
          <summary class="font-medium">
            <.icon name="hero-cpu-chip" class="size-5" />
            Agents
          </summary>
          <ul>
            <%!-- Sales Discovery --%>
            <li>
              <details open={String.starts_with?(@current_path, "/agents/sales")}>
                <summary>
                  <.icon name="hero-briefcase" class="size-4" />
                  Sales
                </summary>
                <ul>
                  <li>
                    <.link navigate={~p"/agents/sales/bids"} class={active_class(@current_path, "/agents/sales/bids")}>
                      <.icon name="hero-document-text" class="size-4" />
                      Bids
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/agents/sales/prospects"} class={active_class(@current_path, "/agents/sales/prospects")}>
                      <.icon name="hero-magnifying-glass" class="size-4" />
                      Prospects
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/agents/sales/lead-sources"} class={active_class(@current_path, "/agents/sales/lead-sources")}>
                      <.icon name="hero-globe-alt" class="size-4" />
                      Lead Sources
                    </.link>
                  </li>
                </ul>
              </details>
            </li>
          </ul>
        </details>
      </li>

      <%!-- Admin --%>
      <li class="mt-4">
        <.link href={~p"/admin"} class={active_class(@current_path, "/admin")}>
          <.icon name="hero-cog-6-tooth" class="size-5" />
          <span>Ash Admin</span>
        </.link>
      </li>
    </ul>
    """
  end

  defp active_class(current_path, path) do
    if current_path == path or
         (path != "/" and String.starts_with?(current_path, path)) do
      "active"
    else
      ""
    end
  end
end
