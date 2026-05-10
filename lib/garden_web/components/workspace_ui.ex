defmodule GnomeGardenWeb.Components.WorkspaceUI do
  @moduledoc """
  Shared page-shell components for admin-style resource views.

  These components standardize the `index/show/form` presentation used across
  operator and console screens so LiveViews can stay focused on loading data
  and handling events.
  """

  use Phoenix.Component

  import GnomeGardenWeb.CoreComponents
  import GnomeGardenWeb.Components.Protocol, except: [button: 1, empty_state: 1]

  attr :class, :any, default: nil
  attr :max_width, :string, default: "max-w-[112rem]"
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class={["mx-auto space-y-3", @max_width, @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # `eyebrow` is no longer rendered — the rail/tabs chrome already shows the
  # area name. Kept as an accepted attr for source compatibility.
  attr :eyebrow, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class={["flex flex-wrap items-center justify-between gap-3", @class]}>
      <div class="min-w-0 flex-1">
        <h1 class="text-lg font-semibold tracking-tight text-base-content sm:text-xl">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-0.5 text-xs leading-5 text-base-content/60">
          {render_slot(@subtitle)}
        </p>
      </div>

      <div :if={@actions != []} class="flex shrink-0 flex-wrap items-center gap-1.5">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :class, :any, default: nil
  attr :body_class, :any, default: nil
  attr :compact, :boolean, default: false
  slot :actions
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <div class={[
      "overflow-hidden rounded-[1.25rem] bg-white/95 ring-1 ring-inset ring-zinc-900/10 shadow-sm dark:bg-zinc-900/80 dark:ring-white/10",
      @class
    ]}>
      <div
        :if={@title || @description || @actions != []}
        class="border-b border-zinc-200/80 px-3 py-3 dark:border-white/10 sm:px-4 sm:py-3.5 lg:px-5"
      >
        <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div class="space-y-1">
            <h2
              :if={@title}
              class="text-base font-semibold tracking-tight text-base-content sm:text-lg"
            >
              {@title}
            </h2>
            <p :if={@description} class="max-w-4xl text-sm leading-5 text-base-content/70">
              {@description}
            </p>
          </div>

          <div :if={@actions != []} class="flex flex-wrap items-center gap-2 lg:justify-end">
            {render_slot(@actions)}
          </div>
        </div>
      </div>

      <div class={[
        @compact && "p-0",
        !@compact && "px-3 py-3 sm:px-4 sm:py-4 lg:px-5",
        @body_class
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class={[
      "flex flex-col items-center justify-center gap-3 rounded-[1.25rem] border border-dashed border-zinc-300/80 bg-zinc-50/70 px-4 py-8 text-center dark:border-white/10 dark:bg-white/[0.03]",
      @class
    ]}>
      <div
        :if={@icon}
        class="flex size-12 items-center justify-center rounded-full bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300"
      >
        <.icon name={@icon} class="size-6" />
      </div>
      <div class="space-y-1">
        <h3 class="text-base font-semibold text-base-content">{@title}</h3>
        <p :if={@description} class="max-w-md text-sm leading-6 text-base-content/60">
          {@description}
        </p>
      </div>
      <div :if={@action != []} class="pt-1">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, required: true
  attr :value, :string, required: true
  attr :accent, :string, default: "emerald"

  def stat_card(assigns) do
    # Map legacy accent names to daisyUI semantic colors so cards inherit the
    # active theme (garden palette in dark mode).
    accent_classes = %{
      "emerald" => "bg-primary/10 text-primary",
      "sky" => "bg-info/10 text-info",
      "amber" => "bg-warning/10 text-warning",
      "rose" => "bg-error/10 text-error"
    }

    assigns =
      assign(
        assigns,
        :accent_class,
        Map.get(accent_classes, assigns.accent, accent_classes["emerald"])
      )

    ~H"""
    <div class="flex items-center gap-3 rounded-lg border border-base-content/10 bg-base-200 px-3 py-2">
      <div class={["flex size-8 shrink-0 items-center justify-center rounded-md", @accent_class]}>
        <.icon name={@icon} class="size-4" />
      </div>
      <div class="min-w-0 flex-1">
        <div class="flex items-baseline gap-2">
          <span class="text-lg font-semibold leading-none tabular-nums">{@value}</span>
          <span class="truncate text-[11px] font-semibold uppercase tracking-wider text-base-content/60">
            {@title}
          </span>
        </div>
        <p :if={@description} class="mt-0.5 truncate text-[11px] text-base-content/50">
          {@description}
        </p>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil

  def action_card(assigns) do
    ~H"""
    <.hover_card class="h-full" href={@href} navigate={@navigate}>
      <div class="flex flex-col gap-2.5 sm:flex-row sm:items-start sm:gap-3">
        <div class="flex size-8 shrink-0 items-center justify-center rounded-xl bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300 sm:size-9">
          <.icon name={@icon} class="size-4 sm:size-[1.125rem]" />
        </div>
        <div class="min-w-0 space-y-1">
          <h3 class="text-sm font-semibold tracking-tight text-base-content sm:text-base">
            {@title}
          </h3>
          <p class="text-sm leading-5 text-base-content/70">
            {@description}
          </p>
        </div>
      </div>
    </.hover_card>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  def form_section(assigns) do
    ~H"""
    <.section title={@title} description={@description}>
      {render_slot(@inner_block)}
    </.section>
    """
  end

  attr :cancel_path, :string, required: true
  attr :submit_label, :string, default: "Save"
  attr :submitting_label, :string, default: "Saving..."

  def form_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-end gap-2">
      <.button type="button" navigate={@cancel_path}>Cancel</.button>
      <.button type="submit" variant="primary" phx-disable-with={@submitting_label}>
        {@submit_label}
      </.button>
    </div>
    """
  end

  attr :tab, :string, required: true
  attr :current, :string, required: true
  slot :inner_block, required: true

  def tab_button(assigns) do
    ~H"""
    <button
      phx-click="tab"
      phx-value-tab={@tab}
      class={[
        "rounded-full px-4 py-2 text-sm font-medium transition",
        if(@tab == @current,
          do: "bg-emerald-600 text-white shadow-sm shadow-emerald-600/20",
          else:
            "bg-zinc-100 text-zinc-600 hover:bg-zinc-200 hover:text-zinc-900 dark:bg-white/[0.05] dark:text-zinc-300 dark:hover:bg-white/[0.08] dark:hover:text-white"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
