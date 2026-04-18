defmodule GnomeGardenWeb.Components.WorkspaceUI do
  @moduledoc """
  Shared page-shell components for admin-style resource views.

  These components standardize the `index/show/form` presentation used across
  CRM and console screens so LiveViews can stay focused on loading data and
  handling events.
  """

  use Phoenix.Component

  import GnomeGardenWeb.CoreComponents
  import GnomeGardenWeb.Components.Protocol, except: [button: 1, empty_state: 1]

  attr :class, :any, default: nil
  attr :max_width, :string, default: "max-w-7xl"
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class={["mx-auto space-y-8", @max_width, @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :eyebrow, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <section class={[
      "relative overflow-hidden rounded-[2rem] bg-white/90 ring-1 ring-inset ring-zinc-900/10 shadow-sm dark:bg-zinc-900/80 dark:ring-white/10",
      @class
    ]}>
      <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(16,185,129,0.14),transparent_42%),radial-gradient(circle_at_top_right,rgba(14,165,233,0.1),transparent_38%)] dark:bg-[radial-gradient(circle_at_top_left,rgba(16,185,129,0.16),transparent_42%),radial-gradient(circle_at_top_right,rgba(14,165,233,0.12),transparent_38%)]" />
      <div class="relative flex flex-col gap-6 px-6 py-7 sm:px-8 lg:flex-row lg:items-end lg:justify-between">
        <div class="space-y-3">
          <p
            :if={@eyebrow}
            class="text-xs font-semibold uppercase tracking-[0.28em] text-emerald-600 dark:text-emerald-300"
          >
            {@eyebrow}
          </p>
          <div class="space-y-2">
            <h1 class="text-3xl font-semibold tracking-tight text-zinc-950 dark:text-white sm:text-4xl">
              {render_slot(@inner_block)}
            </h1>
            <div
              :if={@subtitle != []}
              class="max-w-3xl text-sm leading-6 text-zinc-600 dark:text-zinc-300"
            >
              {render_slot(@subtitle)}
            </div>
          </div>
        </div>

        <div :if={@actions != []} class="flex flex-wrap items-center gap-3 lg:justify-end">
          {render_slot(@actions)}
        </div>
      </div>
    </section>
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
      "overflow-hidden rounded-[1.75rem] bg-white/95 ring-1 ring-inset ring-zinc-900/10 shadow-sm dark:bg-zinc-900/80 dark:ring-white/10",
      @class
    ]}>
      <div
        :if={@title || @description || @actions != []}
        class="border-b border-zinc-200/80 px-6 py-5 dark:border-white/10 sm:px-7"
      >
        <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div class="space-y-1">
            <h2
              :if={@title}
              class="text-lg font-semibold tracking-tight text-zinc-950 dark:text-white"
            >
              {@title}
            </h2>
            <p :if={@description} class="max-w-3xl text-sm leading-6 text-zinc-600 dark:text-zinc-300">
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
        !@compact && "px-6 py-6 sm:px-7",
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
      "flex flex-col items-center justify-center gap-3 rounded-[1.5rem] border border-dashed border-zinc-300/80 bg-zinc-50/70 px-6 py-12 text-center dark:border-white/10 dark:bg-white/[0.03]",
      @class
    ]}>
      <div
        :if={@icon}
        class="flex size-12 items-center justify-center rounded-full bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300"
      >
        <.icon name={@icon} class="size-6" />
      </div>
      <div class="space-y-1">
        <h3 class="text-base font-semibold text-zinc-900 dark:text-white">{@title}</h3>
        <p :if={@description} class="max-w-md text-sm leading-6 text-zinc-600 dark:text-zinc-400">
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
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :value, :string, required: true
  attr :accent, :string, default: "emerald"

  def stat_card(assigns) do
    accent_classes = %{
      "emerald" => "bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300",
      "sky" => "bg-sky-100 text-sky-700 dark:bg-sky-400/10 dark:text-sky-300",
      "amber" => "bg-amber-100 text-amber-700 dark:bg-amber-400/10 dark:text-amber-300",
      "rose" => "bg-rose-100 text-rose-700 dark:bg-rose-400/10 dark:text-rose-300"
    }

    assigns =
      assign(
        assigns,
        :accent_class,
        Map.get(accent_classes, assigns.accent, accent_classes["emerald"])
      )

    ~H"""
    <.section body_class="p-0">
      <div class="flex items-start gap-4 px-6 py-6 sm:px-7">
        <div class={["flex size-12 shrink-0 items-center justify-center rounded-2xl", @accent_class]}>
          <.icon name={@icon} class="size-6" />
        </div>
        <div class="space-y-2">
          <p class="text-sm font-medium text-zinc-500 dark:text-zinc-400">{@title}</p>
          <p class="text-3xl font-semibold tracking-tight text-zinc-950 dark:text-white">{@value}</p>
          <p class="text-sm leading-6 text-zinc-600 dark:text-zinc-300">{@description}</p>
        </div>
      </div>
    </.section>
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
      <div class="flex items-start gap-4">
        <div class="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300">
          <.icon name={@icon} class="size-6" />
        </div>
        <div class="space-y-1">
          <h3 class="text-lg font-semibold tracking-tight text-zinc-950 dark:text-white">
            {@title}
          </h3>
          <p class="text-sm leading-6 text-zinc-600 dark:text-zinc-300">{@description}</p>
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
    <div class="flex flex-wrap items-center justify-end gap-3">
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
