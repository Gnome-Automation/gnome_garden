defmodule GnomeGardenWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GnomeGardenWeb, :html

  alias GnomeGardenWeb.Components.RailNav

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
    # Layout function — called from controllers and LiveView mounts. The
    # received `assigns` shape isn't always a Phoenix.Component assigns map,
    # so we don't call `assign/3` here; instead we delegate to a function
    # component (`<.app_chrome>`) which gets a clean assigns map.
    ~H"""
    <.app_chrome
      current_path={@current_path}
      current_user={@current_user}
      flash={@flash}
    >
      {@inner_content}
    </.app_chrome>
    """
  end

  attr :current_path, :string, required: true
  attr :current_user, :any, default: nil
  attr :flash, :map, required: true
  slot :inner_block, required: true

  defp app_chrome(assigns) do
    area = RailNav.area_for_path(assigns.current_path)
    active = RailNav.active_dest(assigns.current_path, area)
    open_count = length(RailNav.area_dests(area))

    assigns =
      assigns
      |> assign(:area, area)
      |> assign(:active, active)
      |> assign(:open_count, open_count)

    ~H"""
    <div class="flex h-screen w-full overflow-hidden bg-base-100 text-base-content">
      <%!-- Rail (desktop only) --%>
      <div class="hidden h-full lg:block">
        <RailNav.rail area={@area} />
      </div>

      <div class="flex flex-1 flex-col min-w-0 min-h-0">
        <%!-- Desktop chrome --%>
        <div class="hidden lg:block">
          <RailNav.area_header area={@area} open_count={@open_count}>
            <:extra>
              <.theme_toggle />
              <.header_account_controls current_user={@current_user} />
            </:extra>
          </RailNav.area_header>
          <RailNav.tab_strip area={@area} active_id={@active.id} />
        </div>

        <%!-- Mobile chrome --%>
        <RailNav.mobile_top area={@area} active_label={@active.label}>
          <:actions>
            <.theme_toggle />
            <.header_account_controls current_user={@current_user} />
          </:actions>
        </RailNav.mobile_top>

        <%!-- Single content slot — rendered once so LiveComponents inside have unique IDs --%>
        <main class="flex-1 min-h-0 overflow-auto bg-base-100 px-4 py-4 pb-28 lg:px-6 lg:py-6 lg:pb-6">
          {render_slot(@inner_block)}
        </main>

        <%!-- Mobile bottom bar --%>
        <RailNav.mobile_bar area={@area} />
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Profile dropdown in the header.
  """
  attr :current_user, :any, default: nil
  attr :current_scope, :map, default: nil

  def profile_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost h-auto min-h-0 rounded-full border border-zinc-200 bg-white px-2 py-1 shadow-sm hover:border-emerald-300 hover:bg-emerald-50 dark:border-white/10 dark:bg-zinc-900 dark:hover:bg-white/[0.06]"
      >
        <span class="flex size-8 items-center justify-center rounded-full bg-emerald-600 text-xs font-semibold text-white">
          <%= if @current_user do %>
            {account_initial(@current_user)}
          <% else %>
            ?
          <% end %>
        </span>
        <span class="hidden max-w-40 truncate text-sm font-medium text-base-content/80 sm:block">
          {account_label(@current_user)}
        </span>
        <.icon name="hero-chevron-down" class="hidden size-4 text-zinc-400 sm:block" />
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-50 mt-3 w-64 rounded-2xl border border-zinc-200 bg-white p-2 shadow-xl ring-1 ring-zinc-900/5 dark:border-white/10 dark:bg-zinc-800 dark:ring-white/10"
      >
        <%= if @current_user do %>
          <div class="rounded-xl bg-zinc-50 px-3 py-3 dark:bg-white/[0.04]">
            <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/40">
              Signed In
            </p>
            <div class="mt-1 truncate text-sm font-medium text-base-content">
              {account_label(@current_user)}
            </div>
            <div class="truncate text-xs text-base-content/50">
              {account_email(@current_user)}
            </div>
          </div>
          <div class="my-2 h-px bg-zinc-900/10 dark:bg-white/10" />
          <.link
            href={~p"/sign-out"}
            method="delete"
            class="btn btn-ghost justify-start rounded-xl px-3 text-sm text-zinc-700 hover:bg-rose-50 hover:text-rose-700 dark:text-zinc-300 dark:hover:bg-rose-500/10 dark:hover:text-rose-300"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
          </.link>
        <% else %>
          <div class="rounded-xl bg-zinc-50 px-3 py-3 dark:bg-white/[0.04]">
            <p class="text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/40">
              Account
            </p>
            <p class="mt-1 text-sm text-base-content/80">
              Sign in to work the operator queues.
            </p>
          </div>
          <div class="my-2 h-px bg-zinc-900/10 dark:bg-white/10" />
          <.link
            href={~p"/sign-in"}
            class="btn btn-ghost justify-start rounded-xl px-3 text-sm text-zinc-700 hover:bg-emerald-50 hover:text-emerald-700 dark:text-zinc-300 dark:hover:bg-emerald-500/10 dark:hover:text-emerald-300"
          >
            <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Sign in
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  attr :current_user, :any, default: nil

  def header_account_controls(assigns) do
    ~H"""
    <.profile_dropdown current_user={@current_user} />
    """
  end

  defp account_label(nil), do: "Guest"

  defp account_label(user) do
    user
    |> account_email()
    |> to_string()
    |> String.split("@")
    |> List.first()
  end

  defp account_initial(user) do
    user
    |> account_label()
    |> String.first()
    |> Kernel.||("U")
    |> String.upcase()
  end

  defp account_email(%{email: email}), do: to_string(email)
  defp account_email(_user), do: nil

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
          class="size-4 text-base-content/50 dark:[[data-theme=dark]_&]:text-white"
        />
      </button>
    </div>
    """
  end

  # Embed template files in layouts/* (must be after all attr-decorated functions)
  # This creates the root/1 function from root.html.heex
  embed_templates "layouts/*"
end
