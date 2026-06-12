defmodule GnomeGardenWeb.Finance.RetainerLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    return_to = Map.get(params, "return_to", ~p"/finance/retainers")

    case load_retainer(id, socket.assigns.current_user) do
      {:ok, retainer} ->
        {:ok,
         socket
         |> assign(:page_title, retainer.retainer_number || "Retainer")
         |> assign(:retainer, retainer)
         |> assign(:return_to, return_to)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Retainer not found.")
         |> push_navigate(to: ~p"/finance/retainers")}
    end
  end

  @impl true
  def handle_event("issue", _params, socket) do
    case Finance.issue_retainer(socket.assigns.retainer, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:retainer, reload_retainer!(socket.assigns.retainer.id, socket.assigns.current_user))
         |> put_flash(:info, "Retainer issued — email sent to client.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not issue retainer: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("mark_paid", _params, socket) do
    case Finance.mark_retainer_paid(socket.assigns.retainer, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:retainer, reload_retainer!(socket.assigns.retainer.id, socket.assigns.current_user))
         |> put_flash(:info, "Retainer marked as paid.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not mark retainer as paid: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("resend_email", _params, socket) do
    retainer = Ash.load!(socket.assigns.retainer, [:organization], authorize?: false)
    email = GnomeGarden.Mailer.RetainerEmail.build(retainer)

    case GnomeGarden.Mailer.deliver(email) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Retainer email re-sent.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Email delivery failed — please try again.")}
    end
  end

  @impl true
  def handle_event("void", _params, socket) do
    case Finance.void_retainer(socket.assigns.retainer, actor: socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:retainer, reload_retainer!(socket.assigns.retainer.id, socket.assigns.current_user))
         |> put_flash(:info, "Retainer voided.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not void retainer: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("unapply", %{"id" => application_id}, socket) do
    application = Enum.find(socket.assigns.retainer.applications, &(&1.id == application_id))

    if application do
      case Ash.destroy(application, domain: Finance, actor: socket.assigns.current_user) do
        :ok ->
          {:noreply,
           socket
           |> assign(:retainer, reload_retainer!(socket.assigns.retainer.id, socket.assigns.current_user))
           |> put_flash(:info, "Application removed.")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, "Could not unapply: #{inspect(error)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Application not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Retainers">
        {@retainer.retainer_number || "Retainer"}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@retainer.status_variant}>
              {format_atom(@retainer.status)}
            </.status_badge>
            <span class="text-base-content/40">/</span>
            <span>{(@retainer.organization && @retainer.organization.name) || "No client linked"}</span>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={@return_to}>
            Back
          </.button>
          <%= if @retainer.status == :draft do %>
            <.button phx-click="issue" data-confirm="Issue this retainer and send email to client?">
              Issue
            </.button>
          <% end %>
          <%= if @retainer.status == :issued do %>
            <.button phx-click="mark_paid" data-confirm="Mark this retainer as paid?" variant="primary">
              Mark Paid
            </.button>
          <% end %>
          <%= if @retainer.status in [:issued, :paid] do %>
            <.button phx-click="resend_email">
              Resend Email
            </.button>
          <% end %>
          <%= if @retainer.status == :draft do %>
            <.button navigate={~p"/finance/retainers/#{@retainer.id}/edit?return_to=#{~p"/finance/retainers/#{@retainer.id}"}"}>
              Edit
            </.button>
          <% end %>
          <%= if @retainer.status in [:draft, :issued, :paid] do %>
            <.button phx-click="void" data-confirm="Void this retainer? This cannot be undone easily." variant="danger">
              Void
            </.button>
          <% end %>
        </:actions>
      </.page_header>

      <div class="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Total Amount</p>
          <p class="mt-1 text-sm font-mono font-semibold text-gray-900 dark:text-white">
            $<%= Decimal.round(@retainer.amount, 2) %>
          </p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Applied</p>
          <p class="mt-1 text-sm font-mono font-semibold text-gray-900 dark:text-white">
            $<%= Decimal.round(@retainer.applied_amount, 2) %>
          </p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Balance</p>
          <p class="mt-1 text-sm font-mono font-semibold text-gray-900 dark:text-white">
            $<%= Decimal.round(@retainer.balance_amount, 2) %>
          </p>
        </div>
        <div>
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Received</p>
          <p class="mt-1 text-sm text-gray-900 dark:text-white">
            <%= format_date(@retainer.received_on) %>
          </p>
        </div>
      </div>

      <%= if @retainer.notes do %>
        <div class="mb-6 rounded-lg border border-gray-200 dark:border-white/10 p-4">
          <p class="text-xs font-medium uppercase tracking-wide text-gray-500 mb-1">Notes</p>
          <p class="text-sm text-gray-500 whitespace-pre-wrap"><%= @retainer.notes %></p>
        </div>
      <% end %>

      <.section title="Applications" description="Invoices this retainer has been applied against.">
        <div :if={Enum.empty?(@retainer.applications || [])}>
          <p class="text-sm text-base-content/50">No applications yet.</p>
        </div>

        <div :if={!Enum.empty?(@retainer.applications || [])} class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
            <thead class="bg-gray-50 dark:bg-white/5">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Invoice</th>
                <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Applied On</th>
                <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-gray-500">Amount</th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
              <tr :for={app <- @retainer.applications} class="hover:bg-gray-50 dark:hover:bg-white/5">
                <td class="px-4 py-3 font-mono text-gray-900 dark:text-white">
                  <.link navigate={~p"/finance/invoices/#{app.invoice_id}"} class="hover:underline text-emerald-600 dark:text-emerald-400">
                    <%= (app.invoice && app.invoice.invoice_number) || app.invoice_id %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-gray-500"><%= format_date(app.applied_on) %></td>
                <td class="px-4 py-3 text-right font-mono text-gray-900 dark:text-white">
                  $<%= Decimal.round(app.amount, 2) %>
                </td>
                <td class="px-4 py-3 text-right">
                  <button
                    phx-click="unapply"
                    phx-value-id={app.id}
                    data-confirm="Remove this application? This will reverse the applied amount."
                    class="text-xs text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 font-medium"
                  >
                    Unapply
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_retainer(id, actor) do
    Finance.get_retainer(id,
      actor: actor,
      load: [
        :organization,
        :balance_amount,
        :applied_amount,
        :status_variant,
        applications: [:invoice]
      ]
    )
  end

  defp reload_retainer!(id, actor) do
    case load_retainer(id, actor) do
      {:ok, retainer} -> retainer
      {:error, error} -> raise "failed to reload retainer #{id}: #{inspect(error)}"
    end
  end
end
