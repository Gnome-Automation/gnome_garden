defmodule GnomeGardenWeb.Finance.ChartOfAccountsLive do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.ChartOfAccount

  @impl true
  def mount(_params, _session, socket) do
    accounts = load_accounts()

    {:ok,
     socket
     |> assign(:page_title, "Chart of Accounts")
     |> assign(:accounts, accounts)
     |> assign(:show_new_form, false)
     |> assign(:new_attrs, %{"number" => "", "name" => "", "type" => "", "description" => ""})
     |> assign(:form_error, nil)}
  end

  @impl true
  def handle_event("toggle_new_form", _params, socket) do
    {:noreply, assign(socket, :show_new_form, !socket.assigns.show_new_form)}
  end

  @impl true
  def handle_event("new_form_change", %{"account" => params}, socket) do
    {:noreply, assign(socket, :new_attrs, params)}
  end

  @impl true
  def handle_event("create_account", %{"account" => params}, socket) do
    attrs = %{
      number: parse_integer(params["number"]),
      name: params["name"],
      type: parse_atom(params["type"]),
      description: params["description"]
    }

    case Finance.create_account(attrs, authorize?: false) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(:accounts, load_accounts())
         |> assign(:show_new_form, false)
         |> assign(:new_attrs, %{"number" => "", "name" => "", "type" => "", "description" => ""})
         |> assign(:form_error, nil)
         |> put_flash(:info, "Account created.")}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, format_error(error))}
    end
  end

  @impl true
  def handle_event("deactivate", %{"id" => id}, socket) do
    account = Enum.find(socket.assigns.accounts, &(&1.id == id))

    case Finance.deactivate_account(account, authorize?: false) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:accounts, load_accounts())
         |> put_flash(:info, "Account deactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not deactivate account.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Chart of Accounts
        <:subtitle>
          Master list of GL accounts. System accounts cannot be deleted or deactivated.
        </:subtitle>
        <:actions>
          <.button phx-click="toggle_new_form">
            <%= if @show_new_form, do: "Cancel", else: "Add Account" %>
          </.button>
        </:actions>
      </.page_header>

      <%= if @show_new_form do %>
        <div class="mb-8 rounded-lg border border-gray-200 bg-gray-50 p-6 dark:border-white/10 dark:bg-white/5">
          <h3 class="text-base/7 font-semibold text-gray-900 dark:text-white mb-4">New Account</h3>
          <form phx-submit="create_account" phx-change="new_form_change">
            <div class="grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-6">
              <div class="sm:col-span-1">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Number</label>
                <input type="number" name="account[number]" value={@new_attrs["number"]}
                  class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
              </div>
              <div class="sm:col-span-2">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Name</label>
                <input type="text" name="account[name]" value={@new_attrs["name"]}
                  class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
              </div>
              <div class="sm:col-span-1">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Type</label>
                <div class="relative mt-2">
                  <select name="account[type]"
                    class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10">
                    <option value="">Select…</option>
                    <option value="asset" selected={@new_attrs["type"] == "asset"}>Asset</option>
                    <option value="liability" selected={@new_attrs["type"] == "liability"}>Liability</option>
                    <option value="equity" selected={@new_attrs["type"] == "equity"}>Equity</option>
                    <option value="revenue" selected={@new_attrs["type"] == "revenue"}>Revenue</option>
                    <option value="expense" selected={@new_attrs["type"] == "expense"}>Expense</option>
                  </select>
                </div>
              </div>
              <div class="sm:col-span-2">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Description (optional)</label>
                <input type="text" name="account[description]" value={@new_attrs["description"]}
                  class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
              </div>
            </div>
            <%= if @form_error do %>
              <p class="mt-2 text-sm text-red-600"><%= @form_error %></p>
            <% end %>
            <div class="mt-4 flex gap-3">
              <button type="submit" class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500">
                Create Account
              </button>
              <button type="button" phx-click="toggle_new_form" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">#</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Name</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Type</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Normal Balance</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">System</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Active</th>
              <th class="px-4 py-3"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
            <%= for account <- @accounts do %>
              <tr class={if !account.active, do: "opacity-50"}>
                <td class="px-4 py-3 text-sm font-mono text-gray-900 dark:text-white"><%= account.number %></td>
                <td class="px-4 py-3 text-sm text-gray-900 dark:text-white">
                  <%= account.name %>
                  <%= if account.is_system do %>
                    <span class="ml-1 text-gray-400" title="System account">🔒</span>
                  <% end %>
                </td>
                <td class="px-4 py-3 text-sm text-gray-500 capitalize"><%= account.type %></td>
                <td class="px-4 py-3 text-sm text-gray-500 capitalize"><%= account.normal_balance %></td>
                <td class="px-4 py-3 text-sm text-gray-500"><%= if account.is_system, do: "Yes", else: "—" %></td>
                <td class="px-4 py-3 text-sm text-gray-500"><%= if account.active, do: "Yes", else: "No" %></td>
                <td class="px-4 py-3 text-right text-sm">
                  <%= if !account.is_system && account.active do %>
                    <button phx-click="deactivate" phx-value-id={account.id}
                      class="text-red-600 hover:text-red-800 text-xs font-medium">
                      Deactivate
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </.page>
    """
  end

  defp load_accounts do
    ChartOfAccount
    |> Ash.Query.sort(number: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_atom(""), do: nil
  defp parse_atom(val), do: String.to_existing_atom(val)

  defp format_error(%Ash.Error.Invalid{errors: [first | _]}), do: first.message
  defp format_error(e), do: inspect(e)
end
