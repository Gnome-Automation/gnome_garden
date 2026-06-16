defmodule GnomeGardenWeb.Company.SourceReviewLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultReviewRecords

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Company Sources")
     |> load_items()}
  end

  @impl true
  def handle_event("apply", %{"id" => id}, socket) do
    item = Company.get_company_source_review_item!(id, actor: socket.assigns.current_user)

    {:ok, _item} =
      Company.apply_company_source_review_item(item, actor: socket.assigns.current_user)

    {:noreply, load_items(socket)}
  end

  @impl true
  def handle_event("ignore", %{"id" => id}, socket) do
    item = Company.get_company_source_review_item!(id, actor: socket.assigns.current_user)

    {:ok, _item} =
      Company.ignore_company_source_review_item(item, actor: socket.assigns.current_user)

    {:noreply, load_items(socket)}
  end

  @impl true
  def handle_event("review", %{"id" => id}, socket) do
    item = Company.get_company_source_review_item!(id, actor: socket.assigns.current_user)

    {:ok, _item} =
      Company.review_company_source_review_item(item, actor: socket.assigns.current_user)

    {:noreply, load_items(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Company">
        Sources
        <:subtitle>
          Review source claims before changing company records. This is evidence tracking, not an automatic import.
        </:subtitle>
      </.page_header>

      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <.source_stat label="Applied" value={status_count(@items, :applied)} />
        <.source_stat label="Needs review" value={status_count(@items, :needs_review)} />
        <.source_stat label="Conflict" value={status_count(@items, :conflict)} />
        <.source_stat label="Missing" value={status_count(@items, :missing)} />
      </div>

      <.section
        title="Source Review"
        description="Each item captures a source file, current decision, and recommended handling."
      >
        <div class="space-y-3">
          <.source_item :for={item <- @items} item={item} />
        </div>
      </.section>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp source_stat(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 px-3 py-3">
      <div class="text-[11px] font-semibold uppercase text-base-content/50">{@label}</div>
      <div class="mt-1 text-2xl font-semibold text-base-content">{@value}</div>
    </div>
    """
  end

  attr :item, :any, required: true

  defp source_item(assigns) do
    ~H"""
    <article
      id={"source-review-item-#{@item.key}"}
      class="rounded-lg border border-base-content/10 bg-base-100 p-4"
    >
      <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-base font-semibold text-base-content">{@item.title}</h3>
            <span class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70">
              {labelize(@item.status)}
            </span>
            <span
              :if={@item.target_resource}
              class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70"
            >
              {@item.target_resource}
            </span>
          </div>
          <p class="mt-2 break-words text-sm font-medium text-base-content/70">
            {@item.source_path}
          </p>
          <p :if={@item.summary} class="mt-2 text-sm leading-5 text-base-content/70">
            {@item.summary}
          </p>
          <p :if={@item.recommendation} class="mt-2 text-sm leading-5 text-base-content/60">
            {@item.recommendation}
          </p>
        </div>
        <div class="flex shrink-0 flex-wrap gap-2">
          <.button phx-click="apply" phx-value-id={@item.id}>Apply</.button>
          <.button phx-click="review" phx-value-id={@item.id}>Review</.button>
          <.button phx-click="ignore" phx-value-id={@item.id}>Ignore</.button>
        </div>
      </div>
    </article>
    """
  end

  defp load_items(socket) do
    defaults = DefaultReviewRecords.ensure_defaults()
    profile = defaults.profile

    {:ok, items} =
      Company.list_company_source_review_items_for_profile(profile.id,
        actor: socket.assigns.current_user
      )

    assign(socket, profile: profile, items: items)
  end

  defp status_count(items, status), do: Enum.count(items, &(&1.status == status))

  defp labelize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
