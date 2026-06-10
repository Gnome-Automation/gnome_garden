defmodule GnomeGardenWeb.Operations.ReviewLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Operations.Helpers

  alias GnomeGarden.Operations

  @topics [
    "memory_block:created",
    "memory_block:updated",
    "memory_entry:created",
    "memory_entry:updated",
    "learning_recommendation:created",
    "learning_recommendation:updated"
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Enum.each(@topics, &GnomeGardenWeb.Endpoint.subscribe/1)

    {:ok,
     socket
     |> assign(:page_title, "Review Queue")
     |> assign_review_items()}
  end

  @impl true
  def handle_info(%{topic: topic}, socket)
      when topic in @topics do
    {:noreply, assign_review_items(socket)}
  end

  @impl true
  def handle_event("approve_memory_block", %{"id" => id}, socket) do
    {:noreply,
     review_update(socket, &Operations.get_memory_block/2, id, fn record, actor ->
       Operations.activate_memory_block(record, actor: actor)
     end)}
  end

  def handle_event("reject_memory_block", %{"id" => id}, socket) do
    {:noreply,
     review_update(socket, &Operations.get_memory_block/2, id, fn record, actor ->
       Operations.reject_memory_block(
         record,
         %{rejection_reason: "Rejected from review queue"},
         actor: actor
       )
     end)}
  end

  def handle_event("approve_memory_entry", %{"id" => id}, socket) do
    {:noreply,
     review_update(socket, &Operations.get_memory_entry/2, id, fn record, actor ->
       Operations.approve_memory_entry(record, actor: actor)
     end)}
  end

  def handle_event("reject_memory_entry", %{"id" => id}, socket) do
    {:noreply,
     review_update(socket, &Operations.get_memory_entry/2, id, fn record, actor ->
       Operations.reject_memory_entry(
         record,
         %{rejection_reason: "Rejected from review queue"},
         actor: actor
       )
     end)}
  end

  def handle_event("approve_learning", %{"id" => id}, socket) do
    {:noreply,
     review_update(socket, &Operations.get_learning_recommendation/2, id, fn record, actor ->
       Operations.approve_learning_recommendation(
         record,
         %{review_note: "Approved from review queue"},
         actor: actor
       )
     end)}
  end

  def handle_event("reject_learning", %{"id" => id}, socket) do
    {:noreply,
     review_update(socket, &Operations.get_learning_recommendation/2, id, fn record, actor ->
       Operations.reject_learning_recommendation(
         record,
         %{
           review_note: "Rejected from review queue",
           rejection_reason: "Rejected from review queue"
         },
         actor: actor
       )
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Operations">
        Review Queue
        <:subtitle>
          Govern proposed company memory and learning changes before they become active operating context.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/console/agents"}>
            Agents Console
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-2 sm:grid-cols-3">
        <.stat_card
          title="Memory Blocks"
          value={Integer.to_string(length(@memory_blocks))}
          description="Always-visible company context awaiting review."
          icon="hero-rectangle-stack"
        />
        <.stat_card
          title="Memory Entries"
          value={Integer.to_string(length(@memory_entries))}
          description="Archival observations awaiting review."
          icon="hero-archive-box"
          accent="sky"
        />
        <.stat_card
          title="Learning"
          value={Integer.to_string(length(@learning_recommendations))}
          description="Behavior changes awaiting operator decision."
          icon="hero-light-bulb"
          accent="amber"
        />
      </div>

      <div class="grid gap-3 xl:grid-cols-3">
        <.review_section
          title="Memory Blocks"
          description="Approve durable context blocks that can be injected into workflow prompts."
          empty_title="No pending memory blocks"
          empty_description="New proposed context blocks will appear here."
          items={@memory_blocks}
          approve_event="approve_memory_block"
          reject_event="reject_memory_block"
        />

        <.review_section
          title="Archival Memory"
          description="Approve long-term facts, observations, and decisions for recall."
          empty_title="No pending memory entries"
          empty_description="New archival memory proposals will appear here."
          items={@memory_entries}
          approve_event="approve_memory_entry"
          reject_event="reject_memory_entry"
        />

        <.learning_section items={@learning_recommendations} />
      </div>
    </.page>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :empty_title, :string, required: true
  attr :empty_description, :string, required: true
  attr :items, :list, required: true
  attr :approve_event, :string, required: true
  attr :reject_event, :string, required: true

  defp review_section(assigns) do
    ~H"""
    <.section title={@title} description={@description} compact>
      <div :if={@items == []} class="p-4">
        <.empty_state
          icon="hero-check-circle"
          title={@empty_title}
          description={@empty_description}
        />
      </div>

      <div :if={@items != []} class="divide-y divide-zinc-200 dark:divide-white/10">
        <div :for={item <- @items} class="space-y-3 px-3 py-3 sm:px-4">
          <div class="flex flex-wrap items-center gap-2">
            <.status_badge status={item.status_variant}>{format_atom(item.status)}</.status_badge>
            <.tag color={:sky}>{format_atom(item.scope)}</.tag>
            <span class="text-xs text-base-content/50">{item.scope_key}</span>
          </div>
          <div class="space-y-1">
            <p class="text-sm font-semibold text-base-content">{memory_title(item)}</p>
            <p class="line-clamp-3 text-sm leading-5 text-base-content/65">{item.content}</p>
          </div>
          <div
            :if={review_detail_rows(item) != []}
            class="rounded-lg border border-zinc-200/80 bg-zinc-50/70 p-2 text-xs dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div :for={detail <- review_detail_rows(item)} class="grid gap-1 py-1 sm:grid-cols-3">
              <span class="font-medium uppercase tracking-wide text-base-content/40">
                {detail.label}
              </span>
              <span class="break-words text-base-content/65 sm:col-span-2">{detail.value}</span>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <.button id={"approve-#{item.id}"} phx-click={@approve_event} phx-value-id={item.id}>
              Approve
            </.button>
            <.button id={"reject-#{item.id}"} phx-click={@reject_event} phx-value-id={item.id}>
              Reject
            </.button>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :items, :list, required: true

  defp learning_section(assigns) do
    ~H"""
    <.section
      title="Learning Recommendations"
      description="Approve proposed changes before they alter memory, prompts, filters, or target behavior."
      compact
    >
      <div :if={@items == []} class="p-4">
        <.empty_state
          icon="hero-check-circle"
          title="No pending learning"
          description="New learning recommendations will appear here."
        />
      </div>

      <div :if={@items != []} class="divide-y divide-zinc-200 dark:divide-white/10">
        <div :for={item <- @items} class="space-y-3 px-3 py-3 sm:px-4">
          <div class="flex flex-wrap items-center gap-2">
            <.status_badge status={item.status_variant}>{format_atom(item.status)}</.status_badge>
            <.status_badge status={item.risk_variant}>{format_atom(item.risk_level)}</.status_badge>
            <.tag color={:amber}>{format_atom(item.target_domain)}</.tag>
          </div>
          <div class="space-y-1">
            <p class="text-sm font-semibold text-base-content">{item.title}</p>
            <p
              :if={item.impact_summary}
              class="line-clamp-3 text-sm leading-5 text-base-content/65"
            >
              {item.impact_summary}
            </p>
            <p class="text-xs text-base-content/45">
              {item.target_resource} / {item.target_action}
            </p>
          </div>
          <div class="rounded-lg border border-zinc-200/80 bg-zinc-50/70 p-2 text-xs dark:border-white/10 dark:bg-white/[0.03]">
            <div :for={detail <- learning_detail_rows(item)} class="grid gap-1 py-1 sm:grid-cols-3">
              <span class="font-medium uppercase tracking-wide text-base-content/40">
                {detail.label}
              </span>
              <span class="break-words text-base-content/65 sm:col-span-2">{detail.value}</span>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <.button
              id={"approve-learning-#{item.id}"}
              phx-click="approve_learning"
              phx-value-id={item.id}
            >
              Approve
            </.button>
            <.button
              id={"reject-learning-#{item.id}"}
              phx-click="reject_learning"
              phx-value-id={item.id}
            >
              Reject
            </.button>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  defp assign_review_items(%{assigns: %{current_user: actor}} = socket) do
    assign(socket,
      memory_blocks: load_or_empty(&Operations.list_pending_memory_blocks/1, actor),
      memory_entries: load_or_empty(&Operations.list_pending_memory_entries/1, actor),
      learning_recommendations:
        load_or_empty(&Operations.list_pending_learning_recommendations/1, actor)
    )
  end

  defp load_or_empty(fun, actor) do
    case fun.(actor: actor) do
      {:ok, records} -> records
      {:error, _error} -> []
    end
  end

  defp review_update(socket, get_fun, id, update_fun) do
    actor = socket.assigns.current_user

    with {:ok, record} <- get_fun.(id, actor: actor),
         {:ok, _updated} <- update_fun.(record, actor) do
      socket
      |> put_flash(:info, "Review decision saved.")
      |> assign_review_items()
    else
      {:error, _error} ->
        socket
        |> put_flash(:error, "Review decision could not be saved.")
        |> assign_review_items()
    end
  end

  defp memory_title(%{label: label}) when is_binary(label), do: label
  defp memory_title(%{title: title}) when is_binary(title), do: title
  defp memory_title(%{key: key}) when is_binary(key), do: key
  defp memory_title(%{namespace: namespace}) when is_binary(namespace), do: namespace

  defp review_detail_rows(item) do
    [
      detail_row("Source", atom_label(Map.get(item, :source_type))),
      detail_row("Confidence", decimal_label(Map.get(item, :confidence))),
      detail_row("Namespace", Map.get(item, :namespace)),
      detail_row("Tags", tags_label(Map.get(item, :tags))),
      detail_row("Metadata", map_label(Map.get(item, :metadata)))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp learning_detail_rows(item) do
    [
      detail_row("Change", map_label(item.proposed_change)),
      detail_row("Evidence", map_label(item.evidence)),
      detail_row("Impact", item.impact_summary)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp detail_row(_label, nil), do: nil
  defp detail_row(_label, ""), do: nil
  defp detail_row(label, value), do: %{label: label, value: value}

  defp atom_label(value) when is_atom(value), do: format_atom(value)
  defp atom_label(_value), do: nil

  defp decimal_label(nil), do: nil
  defp decimal_label(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp decimal_label(value), do: to_string(value)

  defp tags_label(tags) when is_list(tags) and tags != [], do: Enum.join(tags, ", ")
  defp tags_label(_tags), do: nil

  defp map_label(map) when is_map(map) and map_size(map) > 0 do
    map
    |> Enum.map(fn {key, value} -> "#{key}: #{scalar_label(value)}" end)
    |> Enum.join(", ")
  end

  defp map_label(_map), do: nil

  defp scalar_label(value) when is_binary(value), do: value
  defp scalar_label(value) when is_atom(value), do: format_atom(value)
  defp scalar_label(value) when is_number(value), do: to_string(value)
  defp scalar_label(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp scalar_label(value), do: Jason.encode!(value)
end
