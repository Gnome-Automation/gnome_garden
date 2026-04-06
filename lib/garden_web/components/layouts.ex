defmodule GnomeGardenWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Nav

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
    <div id="app-shell" class="min-h-screen" phx-hook="SidebarCollapse">
      <%!-- Mobile off-canvas sidebar --%>
      <div
        id="mobile-sidebar-backdrop"
        class="fixed inset-0 z-50 bg-gray-900/80 hidden lg:hidden"
        phx-click={hide_mobile_sidebar()}
      >
      </div>

      <div
        id="mobile-sidebar"
        class="fixed inset-y-0 left-0 z-50 w-72 -translate-x-full transition-transform duration-300 ease-in-out lg:hidden"
      >
        <%!-- Close button --%>
        <div class="absolute top-0 right-0 -mr-12 pt-2">
          <button
            type="button"
            class="ml-1 flex size-10 items-center justify-center rounded-full focus:outline-none focus:ring-2 focus:ring-inset focus:ring-white"
            phx-click={hide_mobile_sidebar()}
          >
            <span class="sr-only">Close sidebar</span>
            <.icon name="hero-x-mark" class="size-6 text-white" />
          </button>
        </div>
        <.sidebar_nav
          id="mobile-nav"
          current_path={@current_path}
          current_user={@current_user}
          nav_counts={assigns[:nav_counts] || %{}}
        />
      </div>

      <%!-- Desktop sidebar (expanded) --%>
      <div
        id="sidebar-expanded"
        class="hidden lg:fixed lg:inset-y-0 lg:z-50 lg:flex lg:w-72 lg:flex-col transition-all duration-200"
      >
        <.sidebar_nav
          id="desktop-nav"
          current_path={@current_path}
          current_user={@current_user}
          nav_counts={assigns[:nav_counts] || %{}}
        />
      </div>

      <%!-- Desktop sidebar (collapsed) --%>
      <div
        id="sidebar-collapsed"
        class="hidden lg:fixed lg:inset-y-0 lg:z-50 lg:w-20 lg:flex-col transition-all duration-200"
      >
        <.sidebar_nav
          id="collapsed-nav"
          current_path={@current_path}
          current_user={@current_user}
          nav_counts={assigns[:nav_counts] || %{}}
          collapsed
        />
      </div>

      <%!-- Main content area --%>
      <div id="main-content" class="transition-all duration-200 lg:pl-72">
        <%!-- Mobile top bar --%>
        <div class="sticky top-0 z-40 flex h-16 shrink-0 items-center gap-x-4 border-b border-gray-200 bg-white px-4 shadow-sm dark:border-white/10 dark:bg-zinc-900 sm:gap-x-6 sm:px-6 lg:hidden">
          <button
            type="button"
            class="-m-2.5 p-2.5 text-gray-700 dark:text-gray-200"
            phx-click={show_mobile_sidebar()}
          >
            <span class="sr-only">Open sidebar</span>
            <.icon name="hero-bars-3" class="size-6" />
          </button>

          <div class="h-6 w-px bg-gray-200 dark:bg-white/10" />

          <div class="flex flex-1 items-center gap-x-4">
            <h1 class="text-sm font-semibold text-gray-900 dark:text-white">
              {@page_title || "Dashboard"}
            </h1>
          </div>

          <.theme_toggle />
        </div>

        <%!-- Page content --%>
        <main class="px-4 py-8 sm:px-6 lg:px-8">
          {@inner_content}
        </main>

        <.flash_group flash={@flash} />
      </div>
    </div>
    """
  end

  defp show_mobile_sidebar do
    JS.remove_class("hidden", to: "#mobile-sidebar-backdrop")
    |> JS.remove_class("-translate-x-full", to: "#mobile-sidebar")
    |> JS.add_class("translate-x-0", to: "#mobile-sidebar")
    |> JS.focus_first(to: "#mobile-sidebar")
  end

  defp hide_mobile_sidebar do
    JS.add_class("hidden", to: "#mobile-sidebar-backdrop")
    |> JS.remove_class("translate-x-0", to: "#mobile-sidebar")
    |> JS.add_class("-translate-x-full", to: "#mobile-sidebar")
  end

  @doc """
  Profile dropdown in the header.
  """
  attr :current_user, :map, default: nil
  attr :current_scope, :map, default: nil

  def profile_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="flex size-8 items-center justify-center rounded-full bg-zinc-900/5 ring-1 ring-zinc-900/10 transition hover:bg-zinc-900/10 dark:bg-white/5 dark:ring-white/10 dark:hover:bg-white/10"
      >
        <span class="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          <%= if @current_user do %>
            {String.first(@current_user.email || "U") |> String.upcase()}
          <% else %>
            ?
          <% end %>
        </span>
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-50 mt-2 w-48 rounded-xl bg-white p-2 shadow-lg ring-1 ring-zinc-900/10 dark:bg-zinc-800 dark:ring-white/10"
      >
        <%= if @current_user do %>
          <div class="px-3 py-2 text-xs text-zinc-500 dark:text-zinc-400 truncate">
            {@current_user.email}
          </div>
          <div class="h-px bg-zinc-900/10 dark:bg-white/10 my-1" />
          <.link
            href={~p"/sign-out"}
            method="delete"
            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-zinc-600 transition hover:bg-zinc-900/5 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/5 dark:hover:text-white"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
          </.link>
        <% else %>
          <.link
            href={~p"/sign-in"}
            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-zinc-600 transition hover:bg-zinc-900/5 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/5 dark:hover:text-white"
          >
            <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Log in
          </.link>
          <.link
            href={~p"/register"}
            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-zinc-600 transition hover:bg-zinc-900/5 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/5 dark:hover:text-white"
          >
            <.icon name="hero-user-plus" class="size-4" /> Register
          </.link>
        <% end %>
      </div>
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
    <div class="flex items-center gap-1 rounded-full bg-zinc-900/5 p-1 ring-1 ring-inset ring-zinc-900/10 dark:bg-white/5 dark:ring-white/10">
      <button
        class="flex size-6 items-center justify-center rounded-full transition [[data-theme=system]_&]:bg-white [[data-theme=system]_&]:shadow-sm dark:[[data-theme=system]_&]:bg-emerald-500"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System theme"
      >
        <.icon
          name="hero-computer-desktop-micro"
          class="size-4 text-zinc-500 [[data-theme=system]_&]:text-zinc-900 dark:text-zinc-400 dark:[[data-theme=system]_&]:text-white"
        />
      </button>

      <button
        class="flex size-6 items-center justify-center rounded-full transition [[data-theme=light]_&]:bg-white [[data-theme=light]_&]:shadow-sm"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light theme"
      >
        <.icon
          name="hero-sun-micro"
          class="size-4 text-zinc-500 [[data-theme=light]_&]:text-zinc-900 dark:text-zinc-400"
        />
      </button>

      <button
        class="flex size-6 items-center justify-center rounded-full transition dark:[[data-theme=dark]_&]:bg-emerald-500"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark theme"
      >
        <.icon
          name="hero-moon-micro"
          class="size-4 text-zinc-500 dark:text-zinc-400 dark:[[data-theme=dark]_&]:text-white"
        />
      </button>
    </div>
    """
  end

  # Embed template files in layouts/* (must be after all attr-decorated functions)
  # This creates the root/1 function from root.html.heex
  embed_templates "layouts/*"
end
