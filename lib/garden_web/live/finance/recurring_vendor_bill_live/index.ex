defmodule GnomeGardenWeb.Finance.RecurringVendorBillLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  require Ash.Query

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Recurring Vendor Bills")
     |> assign(:filter_status, "all")
     |> load_templates()}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter_status, status) |> load_templates()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Recurring Vendor Bills
        <:subtitle>Automatic bill templates that generate draft bills on a schedule.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/recurring-vendor-bills/new"} variant="primary">
            New Template
          </.button>
        </:actions>
      </.page_header>

      <div class="mb-4 flex gap-2 flex-wrap">
        <button
          :for={opt <- [{"all", "All"}, {"active", "Active"}, {"paused", "Paused"}, {"stopped", "Stopped"}]}
          phx-click="filter"
          phx-value-status={elem(opt, 0)}
          class={[
            "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
            if(@filter_status == elem(opt, 0),
              do: "bg-emerald-600 text-white",
              else: "bg-zinc-100 text-zinc-700 hover:bg-zinc-200 dark:bg-white/10 dark:text-white dark:hover:bg-white/20"
            )
          ]}
        >
          {elem(opt, 1)}
        </button>
      </div>

      <div :if={Enum.empty?(@templates)} class="rounded-2xl border border-zinc-200 dark:border-white/10 px-6 py-12 text-center">
        <.icon name="hero-arrow-path" class="mx-auto size-8 text-base-content/30 mb-3" />
        <p class="text-sm text-base-content/50">No recurring bill templates yet.</p>
        <.button navigate={~p"/finance/recurring-vendor-bills/new"} class="mt-4">New Template</.button>
      </div>

      <div :if={!Enum.empty?(@templates)} class="space-y-3">
        <.link
          :for={t <- @templates}
          navigate={~p"/finance/recurring-vendor-bills/#{t.id}"}
          class="flex items-center justify-between rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 transition hover:border-emerald-300 hover:bg-white dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-emerald-400/40"
        >
          <div class="space-y-1">
            <p class="font-medium text-base-content">{t.description}</p>
            <p class="text-sm text-base-content/50">
              {(t.vendor && t.vendor.name) || "Unknown vendor"} · {format_atom(t.interval)} · next {format_date(t.next_due_on)}
            </p>
          </div>
          <div class="flex items-center gap-4">
            <p class="text-sm font-semibold text-base-content">{format_amount(t.amount)}</p>
            <.status_badge status={status_variant(t.status)}>
              {format_atom(t.status)}
            </.status_badge>
          </div>
        </.link>
      </div>
    </.page>
    """
  end

  defp load_templates(socket) do
    require Ash.Query

    query =
      GnomeGarden.Finance.RecurringVendorBill
      |> Ash.Query.load([:vendor])
      |> Ash.Query.sort(inserted_at: :desc)

    query =
      case socket.assigns.filter_status do
        "all" -> query
        status -> Ash.Query.filter(query, status == ^String.to_existing_atom(status))
      end

    templates = Ash.read!(query, domain: Finance, authorize?: false)
    assign(socket, :templates, templates)
  end

  defp status_variant(:active), do: "success"
  defp status_variant(:paused), do: "warning"
  defp status_variant(:stopped), do: "neutral"
  defp status_variant(_), do: "neutral"

end
