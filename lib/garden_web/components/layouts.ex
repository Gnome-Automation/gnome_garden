defmodule GnomeGardenWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Nav

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the current user"
  attr :page_title, :string, default: nil, doc: "the page title"
  attr :current_path, :string, default: "/", doc: "the current request path"

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open min-h-screen">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <%!-- Main content area --%>
      <div class="drawer-content flex flex-col min-h-screen bg-base-300">
        <%!-- Header --%>
        <header class="navbar bg-base-100 border-b border-base-200 sticky top-0 z-30">
          <div class="flex-none lg:hidden">
            <label for="sidebar-drawer" class="btn btn-square btn-ghost drawer-button">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>
          <div class="flex-1 px-2">
            <span class="text-lg font-semibold">{@page_title || "Dashboard"}</span>
          </div>
          <div class="flex-none gap-2">
            <.theme_toggle />
            <.profile_dropdown current_user={@current_user} current_scope={@current_scope} />
          </div>
        </header>

        <%!-- Page content --%>
        <main class="flex-1 p-4 lg:p-6">
          {@inner_content}
        </main>

        <.flash_group flash={@flash} />
      </div>

      <%!-- Sidebar --%>
      <div class="drawer-side z-40">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-64 p-4">
          <%!-- Logo --%>
          <a href="/" class="flex items-center gap-2 px-2 py-4 mb-4 hover:opacity-80">
            <img src={~p"/images/logo.svg"} width="32" class="rounded" />
            <span class="text-xl font-bold">Gnome Garden</span>
          </a>

          <%!-- Navigation --%>
          <.sidebar_nav current_path={@current_path} />
        </aside>
      </div>
    </div>
    """
  end

  @doc """
  Profile dropdown in the header.
  """
  attr :current_user, :map, default: nil
  attr :current_scope, :map, default: nil

  def profile_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar placeholder">
        <div class="bg-neutral text-neutral-content w-10 rounded-full">
          <span :if={@current_user}>{String.first(@current_user.email || "U")}</span>
          <span :if={!@current_user}>?</span>
        </div>
      </div>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-50 w-52 p-2 shadow-lg border border-base-200">
        <%= if @current_user do %>
          <li class="menu-title">
            <span class="truncate">{@current_user.email}</span>
          </li>
          <li>
            <.link href={~p"/sign-out"} method="delete">
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              Log out
            </.link>
          </li>
        <% else %>
          <li>
            <.link href={~p"/sign-in"}>
              <.icon name="hero-arrow-left-on-rectangle" class="size-4" />
              Log in
            </.link>
          </li>
          <li>
            <.link href={~p"/register"}>
              <.icon name="hero-user-plus" class="size-4" />
              Register
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
