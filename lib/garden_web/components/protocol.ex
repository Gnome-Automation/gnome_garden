defmodule GnomeGardenWeb.Components.Protocol do
  @moduledoc """
  Protocol-inspired UI components.
  Reusable cards, patterns, and styling from the Tailwind Plus Protocol template.
  """
  use Phoenix.Component

  @doc """
  Renders a grid pattern SVG for card backgrounds.
  """
  attr :id, :string, required: true
  attr :width, :integer, default: 72
  attr :height, :integer, default: 56
  attr :x, :string, default: "50%"
  attr :y, :integer, default: 16
  attr :squares, :list, default: []
  attr :class, :string, default: nil

  def grid_pattern(assigns) do
    ~H"""
    <svg
      aria-hidden="true"
      class={["absolute inset-x-0 inset-y-[-30%] h-[160%] w-full skew-y-[-18deg]", @class]}
    >
      <defs>
        <pattern id={@id} width={@width} height={@height} patternUnits="userSpaceOnUse" x={@x} y={@y}>
          <path d="M.5 56V.5H72" fill="none" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" stroke-width="0" fill={"url(##{@id})"} />
      <svg x={@x} y={@y} class="overflow-visible">
        <rect
          :for={{sq_x, sq_y} <- @squares}
          stroke-width="0"
          width={@width + 1}
          height={@height + 1}
          x={sq_x * @width}
          y={sq_y * @height}
        />
      </svg>
    </svg>
    """
  end

  @doc """
  Renders a Protocol-style resource card with grid pattern background.
  Used for navigation cards, feature highlights, etc.
  """
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, default: nil
  attr :pattern_y, :integer, default: 16
  attr :squares, :list, default: [[0, 1], [1, 3]]
  attr :id, :string, required: true

  slot :inner_block

  def resource_card(assigns) do
    ~H"""
    <div class="group relative flex rounded-2xl bg-zinc-50 transition-shadow hover:shadow-md hover:shadow-zinc-900/5 dark:bg-white/2.5 dark:hover:shadow-black/5">
      <%!-- Background pattern --%>
      <div class="pointer-events-none">
        <div class="absolute inset-0 rounded-2xl [mask-image:linear-gradient(white,transparent)] transition duration-300 group-hover:opacity-50">
          <.grid_pattern
            id={"#{@id}-pattern"}
            y={@pattern_y}
            squares={@squares}
            class="fill-black/[0.02] stroke-black/5 dark:fill-white/[0.01] dark:stroke-white/[0.025]"
          />
        </div>
        <%!-- Hover gradient --%>
        <div class="absolute inset-0 rounded-2xl bg-gradient-to-r from-[#D7EDEA] to-[#F4FBDF] opacity-0 transition duration-300 group-hover:opacity-100 dark:from-[#202D2E] dark:to-[#303428]" />
      </div>

      <%!-- Ring border --%>
      <div class="absolute inset-0 rounded-2xl ring-1 ring-inset ring-zinc-900/[0.075] group-hover:ring-base-content/10 dark:group-hover:ring-white/20" />

      <%!-- Content --%>
      <div class="relative w-full rounded-2xl px-4 pb-4 pt-16">
        <%!-- Icon --%>
        <div
          :if={@icon}
          class="flex h-7 w-7 items-center justify-center rounded-full bg-zinc-900/5 ring-1 ring-zinc-900/25 backdrop-blur-[2px] transition duration-300 group-hover:bg-white/50 group-hover:ring-zinc-900/25 dark:bg-white/[0.075] dark:ring-white/15 dark:group-hover:bg-emerald-300/10 dark:group-hover:ring-emerald-400"
        >
          <span class={"#{@icon} h-5 w-5 fill-zinc-700/10 stroke-zinc-700 transition-colors duration-300 group-hover:stroke-zinc-900 dark:fill-white/10 dark:stroke-zinc-400 dark:group-hover:fill-emerald-300/10 dark:group-hover:stroke-emerald-400"} />
        </div>

        <%!-- Title --%>
        <h3 class="mt-4 text-sm/7 font-semibold text-base-content">
          <.link :if={@navigate} navigate={@navigate}>
            <span class="absolute inset-0 rounded-2xl" />
            {@title}
          </.link>
          <a :if={@href && !@navigate} href={@href}>
            <span class="absolute inset-0 rounded-2xl" />
            {@title}
          </a>
        </h3>

        <%!-- Description --%>
        <p :if={@description} class="mt-1 text-sm text-base-content/60">
          {@description}
        </p>

        <%!-- Custom content --%>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a Protocol-style tag/badge.
  """
  attr :color, :atom, default: :zinc, values: [:emerald, :sky, :amber, :rose, :zinc]
  attr :variant, :atom, default: :medium, values: [:small, :medium]
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={[
      "font-mono text-[0.625rem]/6 font-semibold",
      variant_class(@variant),
      color_class(@color, @variant)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp variant_class(:small), do: ""
  defp variant_class(:medium), do: "rounded-lg px-1.5 ring-1 ring-inset"

  defp color_class(:emerald, :small), do: "text-primary"

  defp color_class(:emerald, :medium),
    do: "ring-emerald-300 dark:ring-emerald-400/30 bg-emerald-400/10 text-primary"

  defp color_class(:sky, :small), do: "text-sky-500"

  defp color_class(:sky, :medium),
    do:
      "ring-sky-300 bg-sky-400/10 text-sky-500 dark:ring-sky-400/30 dark:bg-sky-400/10 dark:text-sky-400"

  defp color_class(:amber, :small), do: "text-amber-500"

  defp color_class(:amber, :medium),
    do:
      "ring-amber-300 bg-amber-400/10 text-amber-500 dark:ring-amber-400/30 dark:bg-amber-400/10 dark:text-amber-400"

  defp color_class(:rose, :small), do: "text-red-500 dark:text-rose-500"

  defp color_class(:rose, :medium),
    do:
      "ring-rose-200 bg-rose-50 text-red-500 dark:ring-rose-500/20 dark:bg-rose-400/10 dark:text-rose-400"

  defp color_class(:zinc, :small), do: "text-base-content/40"

  defp color_class(:zinc, :medium),
    do:
      "ring-zinc-200 bg-zinc-50 text-zinc-500 dark:ring-zinc-500/20 dark:bg-zinc-400/10 dark:text-zinc-400"

  @doc """
  Renders a Protocol-style button.
  """
  attr :variant, :atom,
    default: :primary,
    values: [:primary, :secondary, :filled, :outline, :text]

  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <.link :if={@navigate} navigate={@navigate} class={[button_class(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    <a :if={@href && !@navigate} href={@href} class={[button_class(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </a>
    <button :if={!@href && !@navigate} class={[button_class(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_class(:primary) do
    "inline-flex gap-0.5 justify-center overflow-hidden text-sm font-medium transition rounded-full bg-zinc-900 py-1 px-3 text-white hover:bg-zinc-700 dark:bg-emerald-400/10 dark:text-emerald-400 dark:ring-1 dark:ring-inset dark:ring-emerald-400/20 dark:hover:bg-emerald-400/10 dark:hover:text-emerald-300 dark:hover:ring-emerald-300"
  end

  defp button_class(:secondary) do
    "inline-flex gap-0.5 justify-center overflow-hidden text-sm font-medium transition rounded-full bg-zinc-100 py-1 px-3 text-zinc-900 hover:bg-zinc-200 dark:bg-zinc-800/40 dark:text-zinc-400 dark:ring-1 dark:ring-inset dark:ring-zinc-800 dark:hover:bg-zinc-800 dark:hover:text-zinc-300"
  end

  defp button_class(:filled) do
    "inline-flex gap-0.5 justify-center overflow-hidden text-sm font-medium transition rounded-full bg-zinc-900 py-1 px-3 text-white hover:bg-zinc-700 dark:bg-emerald-500 dark:text-white dark:hover:bg-emerald-400"
  end

  defp button_class(:outline) do
    "inline-flex gap-0.5 justify-center overflow-hidden text-sm font-medium transition rounded-full py-1 px-3 text-zinc-700 ring-1 ring-inset ring-zinc-900/10 hover:bg-zinc-900/[0.025] hover:text-zinc-900 dark:text-zinc-400 dark:ring-white/10 dark:hover:bg-white/5 dark:hover:text-white"
  end

  defp button_class(:text) do
    "inline-flex gap-0.5 justify-center overflow-hidden text-sm font-medium transition text-emerald-500 hover:text-primary dark:hover:text-emerald-500"
  end

  @doc """
  Simple card container with Protocol styling.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl bg-zinc-50 ring-1 ring-inset ring-zinc-900/[0.075] dark:bg-white/[0.025] dark:ring-white/10",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Interactive card with hover effects (simpler than resource_card).
  """
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def hover_card(assigns) do
    ~H"""
    <div class={[
      "group relative rounded-2xl bg-zinc-50 p-4 transition-all hover:shadow-md hover:shadow-zinc-900/5 dark:bg-white/[0.025] dark:hover:shadow-black/5",
      @class
    ]}>
      <div class="absolute inset-0 rounded-2xl ring-1 ring-inset ring-zinc-900/[0.075] transition group-hover:ring-base-content/10 dark:group-hover:ring-white/20" />
      <div class="relative">
        <.link :if={@navigate} navigate={@navigate} class="absolute inset-0 rounded-2xl">
          <span class="sr-only">View</span>
        </.link>
        <a :if={@href && !@navigate} href={@href} class="absolute inset-0 rounded-2xl" />
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Protocol-style note/info box with emerald accent.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def note(assigns) do
    ~H"""
    <div class={[
      "my-6 flex gap-2.5 rounded-2xl border border-emerald-500/20 bg-emerald-50/50 p-4 text-sm/6 text-emerald-900 dark:border-emerald-500/30 dark:bg-emerald-500/5 dark:text-emerald-200",
      @class
    ]}>
      <svg
        viewBox="0 0 16 16"
        aria-hidden="true"
        class="mt-1 h-4 w-4 flex-none fill-emerald-500 stroke-white dark:fill-emerald-200/20 dark:stroke-emerald-200"
      >
        <circle cx="8" cy="8" r="8" stroke-width="0" />
        <path
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M6.75 7.75h1.5v3.5"
        />
        <circle cx="8" cy="4" r=".5" fill="none" />
      </svg>
      <div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Protocol-style warning box with amber accent.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def warning(assigns) do
    ~H"""
    <div class={[
      "my-6 flex gap-2.5 rounded-2xl border border-amber-500/20 bg-amber-50/50 p-4 text-sm/6 text-amber-900 dark:border-amber-500/30 dark:bg-amber-500/5 dark:text-amber-200",
      @class
    ]}>
      <svg
        viewBox="0 0 16 16"
        aria-hidden="true"
        class="mt-1 h-4 w-4 flex-none fill-amber-500 stroke-white dark:fill-amber-200/20 dark:stroke-amber-200"
      >
        <path d="M8 1.5l6.5 13H1.5L8 1.5z" stroke-width="0" />
        <path
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M8 6v3"
        />
        <circle cx="8" cy="11.5" r=".5" fill="none" />
      </svg>
      <div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Protocol-style divider/border.
  """
  attr :class, :string, default: nil

  def divider(assigns) do
    ~H"""
    <div class={["border-t border-zinc-900/5 dark:border-white/5", @class]} />
    """
  end

  @doc """
  Protocol-style section heading with optional tag.
  """
  attr :level, :integer, default: 2
  attr :id, :string, default: nil
  attr :tag, :string, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def heading(assigns) do
    ~H"""
    <div class={@class}>
      <div :if={@tag || @label} class="flex items-center gap-x-3">
        <.tag :if={@tag}>{@tag}</.tag>
        <span :if={@tag && @label} class="h-0.5 w-0.5 rounded-full bg-zinc-300 dark:bg-zinc-600" />
        <span :if={@label} class="font-mono text-xs text-zinc-400">{@label}</span>
      </div>
      <%= case @level do %>
        <% 1 -> %>
          <h1
            id={@id}
            class={[
              @tag || @label,
              "mt-2 scroll-mt-32",
              "text-2xl font-bold text-base-content"
            ]}
          >
            {render_slot(@inner_block)}
          </h1>
        <% 2 -> %>
          <h2
            id={@id}
            class={[
              @tag || (@label && "mt-2 scroll-mt-32"),
              "text-xl font-semibold text-base-content"
            ]}
          >
            {render_slot(@inner_block)}
          </h2>
        <% 3 -> %>
          <h3
            id={@id}
            class={[
              @tag || (@label && "mt-2 scroll-mt-32"),
              "text-lg font-semibold text-base-content"
            ]}
          >
            {render_slot(@inner_block)}
          </h3>
        <% _ -> %>
          <h4
            id={@id}
            class={[
              @tag || (@label && "mt-2 scroll-mt-32"),
              "text-base font-semibold text-base-content"
            ]}
          >
            {render_slot(@inner_block)}
          </h4>
      <% end %>
    </div>
    """
  end

  @doc """
  Protocol-style property list container.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def properties(assigns) do
    ~H"""
    <div class={["my-6", @class]}>
      <ul role="list" class="m-0 list-none divide-y divide-zinc-900/5 p-0 dark:divide-white/5">
        {render_slot(@inner_block)}
      </ul>
    </div>
    """
  end

  @doc """
  Protocol-style property item.
  """
  attr :name, :string, required: true
  attr :type, :string, default: nil
  slot :inner_block, required: true

  def property(assigns) do
    ~H"""
    <li class="m-0 px-0 py-4 first:pt-0 last:pb-0">
      <dl class="m-0 flex flex-wrap items-center gap-x-3 gap-y-2">
        <dt class="sr-only">Name</dt>
        <dd>
          <code class="rounded bg-zinc-100 px-1.5 py-0.5 text-sm font-medium text-zinc-900 dark:bg-zinc-800 dark:text-zinc-200">
            {@name}
          </code>
        </dd>
        <dt :if={@type} class="sr-only">Type</dt>
        <dd :if={@type} class="font-mono text-xs text-base-content/40">
          {@type}
        </dd>
        <dt class="sr-only">Description</dt>
        <dd class="w-full flex-none text-sm text-base-content/60">
          {render_slot(@inner_block)}
        </dd>
      </dl>
    </li>
    """
  end

  @doc """
  Protocol-style feedback form ("Was this helpful?").
  """
  attr :class, :string, default: nil

  def feedback(assigns) do
    ~H"""
    <div class={["relative h-8", @class]}>
      <form class="absolute inset-0 flex items-center justify-center gap-6 md:justify-start">
        <p class="text-sm text-base-content/60">
          Was this helpful?
        </p>
        <div class="group grid h-8 grid-cols-[1fr_1px_1fr] overflow-hidden rounded-full border border-zinc-900/10 dark:border-white/10">
          <button
            type="button"
            class="px-3 text-sm font-medium text-zinc-600 transition hover:bg-zinc-900/[0.025] hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/5 dark:hover:text-white"
          >
            Yes
          </button>
          <div class="bg-zinc-900/10 dark:bg-white/10" />
          <button
            type="button"
            class="px-3 text-sm font-medium text-zinc-600 transition hover:bg-zinc-900/[0.025] hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-white/5 dark:hover:text-white"
          >
            No
          </button>
        </div>
      </form>
    </div>
    """
  end

  @doc """
  Protocol-style guide/link list item.
  """
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def guide_link(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-semibold text-base-content">
        {@title}
      </h3>
      <p :if={@description} class="mt-1 text-sm text-base-content/60">
        {@description}
      </p>
      <p class="mt-4">
        <.button href={@href} navigate={@navigate} variant={:text}>
          Read more
          <svg viewBox="0 0 20 20" fill="none" aria-hidden="true" class="mt-0.5 h-5 w-5 -mr-1">
            <path
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m11.5 6.5 3 3.5m0 0-3 3.5m3-3.5h-9"
            />
          </svg>
        </.button>
      </p>
    </div>
    """
  end

  @doc """
  Protocol-style empty state.
  """
  attr :title, :string, default: "No results"
  attr :description, :string, default: nil
  attr :icon, :string, default: "hero-inbox"
  attr :class, :string, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class={["flex flex-col items-center justify-center py-16 text-center", @class]}>
      <div class="flex h-12 w-12 items-center justify-center rounded-full bg-base-300">
        <span class={"#{@icon} h-6 w-6 text-zinc-400"} />
      </div>
      <h3 class="mt-4 text-sm font-semibold text-base-content">{@title}</h3>
      <p :if={@description} class="mt-1 text-sm text-base-content/60">{@description}</p>
      <div :if={@inner_block != []} class="mt-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Protocol-style stat card.
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :change, :string, default: nil
  attr :change_type, :atom, default: :neutral, values: [:positive, :negative, :neutral]

  def stat(assigns) do
    ~H"""
    <div class="rounded-2xl bg-zinc-50 p-6 ring-1 ring-inset ring-zinc-900/[0.075] dark:bg-white/[0.025] dark:ring-white/10">
      <p class="text-sm font-medium text-base-content/50">{@label}</p>
      <p class="mt-2 flex items-baseline gap-2">
        <span class="text-3xl font-semibold tracking-tight text-base-content">
          {@value}
        </span>
        <span
          :if={@change}
          class={[
            "text-sm font-medium",
            @change_type == :positive && "text-primary",
            @change_type == :negative && "text-error",
            @change_type == :neutral && "text-base-content/50"
          ]}
        >
          {@change}
        </span>
      </p>
    </div>
    """
  end

  @doc """
  Protocol-style avatar.
  """
  attr :src, :string, default: nil
  attr :alt, :string, default: ""
  attr :initials, :string, default: nil
  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg, :xl]
  attr :class, :string, default: nil

  def avatar(assigns) do
    ~H"""
    <%= if @src do %>
      <img src={@src} alt={@alt} class={[avatar_size(@size), "rounded-full object-cover", @class]} />
    <% else %>
      <span class={[
        avatar_size(@size),
        "inline-flex items-center justify-center rounded-full bg-zinc-100 text-zinc-600 ring-1 ring-inset ring-zinc-900/10 dark:bg-zinc-800 dark:text-zinc-400 dark:ring-white/10",
        @class
      ]}>
        <span class={avatar_text_size(@size)}>{@initials || "?"}</span>
      </span>
    <% end %>
    """
  end

  defp avatar_size(:xs), do: "h-6 w-6"
  defp avatar_size(:sm), do: "h-8 w-8"
  defp avatar_size(:md), do: "h-10 w-10"
  defp avatar_size(:lg), do: "h-12 w-12"
  defp avatar_size(:xl), do: "h-16 w-16"

  defp avatar_text_size(:xs), do: "text-xs font-medium"
  defp avatar_text_size(:sm), do: "text-xs font-medium"
  defp avatar_text_size(:md), do: "text-sm font-medium"
  defp avatar_text_size(:lg), do: "text-base font-medium"
  defp avatar_text_size(:xl), do: "text-lg font-medium"

  @doc """
  Protocol-style badge/pill for status indicators.
  """
  attr :status, :atom, default: :default, values: [:default, :success, :warning, :error, :info]
  slot :inner_block, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium",
      status_class(@status)
    ]}>
      <span class={["h-1.5 w-1.5 rounded-full", status_dot_class(@status)]} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp status_class(:default), do: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"

  defp status_class(:success),
    do: "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-400"

  defp status_class(:warning),
    do: "bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-400"

  defp status_class(:error), do: "bg-rose-50 text-rose-700 dark:bg-rose-500/10 dark:text-rose-400"
  defp status_class(:info), do: "bg-sky-50 text-sky-700 dark:bg-sky-500/10 dark:text-sky-400"

  defp status_dot_class(:default), do: "bg-zinc-400 dark:bg-zinc-500"
  defp status_dot_class(:success), do: "bg-emerald-500 dark:bg-emerald-400"
  defp status_dot_class(:warning), do: "bg-amber-500 dark:bg-amber-400"
  defp status_dot_class(:error), do: "bg-rose-500 dark:bg-rose-400"
  defp status_dot_class(:info), do: "bg-sky-500 dark:bg-sky-400"

  @doc """
  Simple status dot indicator (like in activity tables).
  Just the colored dot with background ring.
  """
  attr :status, :atom, default: :default, values: [:default, :success, :warning, :error, :info]
  attr :class, :string, default: nil

  def status_dot(assigns) do
    ~H"""
    <div class={[
      "flex-none rounded-full p-1",
      dot_bg_class(@status),
      @class
    ]}>
      <div class={["size-1.5 rounded-full bg-current"]} />
    </div>
    """
  end

  defp dot_bg_class(:default),
    do: "bg-zinc-600/10 text-zinc-600 dark:bg-zinc-400/10 dark:text-zinc-400"

  defp dot_bg_class(:success),
    do: "bg-emerald-600/10 text-emerald-600 dark:bg-emerald-400/10 dark:text-emerald-400"

  defp dot_bg_class(:warning),
    do: "bg-amber-600/10 text-amber-600 dark:bg-amber-400/10 dark:text-amber-400"

  defp dot_bg_class(:error),
    do: "bg-rose-600/10 text-rose-600 dark:bg-rose-400/10 dark:text-rose-400"

  defp dot_bg_class(:info), do: "bg-sky-600/10 text-sky-600 dark:bg-sky-400/10 dark:text-sky-400"

  @doc """
  Small inline badge/pill (like branch names, tags).
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "rounded-md bg-zinc-100 px-2 py-1 text-xs font-medium text-zinc-600",
      "dark:bg-zinc-700/40 dark:text-zinc-400 dark:outline dark:-outline-offset-1 dark:outline-white/10",
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Mono-styled text (for commit hashes, IDs, code).
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def mono(assigns) do
    ~H"""
    <span class={["font-mono text-sm/6 text-base-content/50", @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Table cell with user avatar and name.
  """
  attr :src, :string, default: nil
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def user_cell(assigns) do
    ~H"""
    <div class={["flex items-center gap-x-4", @class]}>
      <%= if @src do %>
        <img
          src={@src}
          alt=""
          class="size-8 rounded-full bg-base-300 dark:outline dark:outline-white/10"
        />
      <% else %>
        <span class="inline-flex size-8 items-center justify-center rounded-full bg-zinc-100 text-zinc-600 ring-1 ring-inset ring-zinc-200 dark:bg-zinc-800 dark:text-zinc-400 dark:ring-white/10">
          <span class="text-xs font-medium">{String.first(@name) |> String.upcase()}</span>
        </span>
      <% end %>
      <div class="truncate text-sm/6 font-medium text-base-content">{@name}</div>
    </div>
    """
  end

  @doc """
  Status cell with dot and label (for table status columns).
  """
  attr :status, :atom, default: :default, values: [:default, :success, :warning, :error, :info]
  attr :label, :string, required: true
  attr :time, :string, default: nil
  attr :class, :string, default: nil

  def status_cell(assigns) do
    ~H"""
    <div class={["flex items-center justify-end gap-x-2 sm:justify-start", @class]}>
      <time :if={@time} class="text-zinc-500 sm:hidden dark:text-zinc-400">{@time}</time>
      <.status_dot status={@status} />
      <div class="hidden text-zinc-900 sm:block dark:text-white">{@label}</div>
    </div>
    """
  end
end
