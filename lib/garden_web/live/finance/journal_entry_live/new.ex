defmodule GnomeGardenWeb.Finance.JournalEntryLive.New do
  use GnomeGardenWeb, :live_view

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.ChartOfAccount

  @empty_line %{"account_id" => "", "description" => "", "debit" => "", "credit" => ""}

  @impl true
  def mount(_params, _session, socket) do
    accounts = load_active_accounts()

    {:ok,
     socket
     |> assign(:page_title, "New Manual Journal Entry")
     |> assign(:accounts, accounts)
     |> assign(:date, Date.utc_today() |> Date.to_iso8601())
     |> assign(:description, "")
     |> assign(:lines, [@empty_line, @empty_line])
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("change", params, socket) do
    lines =
      case params["lines"] do
        nil -> socket.assigns.lines
        map_or_list -> normalize_lines(map_or_list)
      end

    {:noreply,
     socket
     |> assign(:date, params["date"] || socket.assigns.date)
     |> assign(:description, params["description"] || socket.assigns.description)
     |> assign(:lines, lines)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("add_line", _params, socket) do
    {:noreply, assign(socket, :lines, socket.assigns.lines ++ [@empty_line])}
  end

  @impl true
  def handle_event("remove_line", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    lines = List.delete_at(socket.assigns.lines, idx)
    lines = if length(lines) < 2, do: lines ++ [@empty_line], else: lines
    {:noreply, assign(socket, :lines, lines)}
  end

  @impl true
  def handle_event("save", params, socket) do
    mode = if params["_action"] == "post", do: :post, else: :draft
    do_save(params, socket, mode)
  end

  defp do_save(params, socket, mode) do
    lines_raw = normalize_lines(params["lines"])
    date_str = params["date"] || ""
    description = params["description"] || ""

    with {:ok, date} <- parse_date(date_str),
         {:ok, lines} <- parse_lines(lines_raw),
         {:ok, entry} <-
           Finance.create_journal_entry(
             %{date: date, description: description, entry_type: :manual},
             authorize?: false
           ),
         :ok <- create_lines(entry.id, lines),
         {:ok, final_entry} <- maybe_post(entry, mode) do
      {:noreply,
       socket
       |> put_flash(:info, if(mode == :post, do: "Entry posted.", else: "Entry saved as draft."))
       |> push_navigate(to: ~p"/finance/journal-entries/#{final_entry.id}")}
    else
      {:error, msg} when is_binary(msg) ->
        {:noreply, assign(socket, :error, msg)}

      {:error, error} ->
        {:noreply, assign(socket, :error, format_error(error))}
    end
  end

  defp parse_date(""), do: {:error, "Date is required"}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, "Invalid date"}
    end
  end

  defp parse_lines(lines_raw) do
    parsed =
      lines_raw
      |> Enum.reject(fn l -> l["account_id"] == "" end)
      |> Enum.map(&parse_line/1)

    errors = Enum.filter(parsed, &match?({:error, _}, &1))

    if errors == [] && length(parsed) >= 2 do
      {:ok, Enum.map(parsed, fn {:ok, l} -> l end)}
    else
      cond do
        length(parsed) < 2 -> {:error, "At least two lines are required"}
        true -> {:error, elem(hd(errors), 1)}
      end
    end
  end

  defp parse_line(l) do
    debit = parse_decimal(l["debit"])
    credit = parse_decimal(l["credit"])

    cond do
      is_nil(debit) && is_nil(credit) ->
        {:error, "Each line needs either a debit or credit amount"}

      !is_nil(debit) && !is_nil(credit) ->
        {:error, "A line cannot have both debit and credit"}

      true ->
        {:ok, %{account_id: l["account_id"], description: l["description"] || "", debit: debit, credit: credit}}
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {d, ""} -> if Decimal.positive?(d), do: d, else: nil
      _ -> nil
    end
  end

  defp create_lines(entry_id, lines) do
    Enum.reduce_while(lines, :ok, fn line, :ok ->
      case Finance.create_journal_entry_line(
             Map.put(line, :journal_entry_id, entry_id),
             authorize?: false
           ) do
        {:ok, _} -> {:cont, :ok}
        {:error, err} -> {:halt, {:error, format_error(err)}}
      end
    end)
  end

  defp maybe_post(entry, :draft), do: {:ok, entry}

  defp maybe_post(entry, :post) do
    loaded = Finance.get_journal_entry(entry.id, authorize?: false, load: [:lines])

    case loaded do
      {:ok, e} -> Finance.post_journal_entry(e, authorize?: false)
      err -> err
    end
  end

  defp load_active_accounts do
    ChartOfAccount
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(number: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp total_debits(lines) do
    lines
    |> Enum.map(&parse_decimal(&1["debit"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp total_credits(lines) do
    lines
    |> Enum.map(&parse_decimal(&1["credit"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp balanced?(lines) do
    d = total_debits(lines)
    c = total_credits(lines)
    Decimal.positive?(d) && Decimal.equal?(d, c)
  end

  defp format_amount(d) do
    "$#{Decimal.round(d, 2)}"
  end

  # Phoenix sends indexed form params as a map %{"0" => %{...}, "1" => %{...}}.
  # Normalize back to a sorted list so template and parse logic always see a list.
  defp normalize_lines(nil), do: []
  defp normalize_lines(lines) when is_list(lines), do: lines

  defp normalize_lines(lines) when is_map(lines) do
    lines
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp format_error(%Ash.Error.Invalid{errors: [first | _]}), do: first.message
  defp format_error(e), do: inspect(e)

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance / Journal Entries">
        New Manual Entry
        <:subtitle>Create a manual double-entry journal entry.</:subtitle>
        <:actions>
          <.button navigate={~p"/finance/journal-entries"}>Cancel</.button>
        </:actions>
      </.page_header>

      <%= if @error do %>
        <div class="mb-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
          <%= @error %>
        </div>
      <% end %>

      <form id="je-form" phx-change="change" phx-submit="save">
        <div class="mb-6 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-6">
          <div class="sm:col-span-2">
            <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Date</label>
            <input type="date" name="date" value={@date} required
              class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
          </div>
          <div class="sm:col-span-4">
            <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Description</label>
            <input type="text" name="description" value={@description} required placeholder="Memo / description"
              class="mt-2 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10" />
          </div>
        </div>

        <div class="overflow-hidden rounded-lg border border-gray-200 dark:border-white/10 mb-3">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
            <thead class="bg-gray-50 dark:bg-white/5">
              <tr>
                <th class="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Account</th>
                <th class="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-gray-500">Description</th>
                <th class="px-3 py-2 text-right text-xs font-semibold uppercase tracking-wide text-gray-500 w-32">Debit</th>
                <th class="px-3 py-2 text-right text-xs font-semibold uppercase tracking-wide text-gray-500 w-32">Credit</th>
                <th class="px-3 py-2 w-8"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 bg-white dark:divide-white/5 dark:bg-transparent">
              <%= for {line, idx} <- Enum.with_index(@lines) do %>
                <tr>
                  <td class="px-3 py-2">
                    <div class="relative">
                      <select name={"lines[#{idx}][account_id]"}
                        class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10">
                        <option value="">Select account…</option>
                        <%= for account <- @accounts do %>
                          <option value={account.id} selected={line["account_id"] == to_string(account.id)}>
                            <%= account.number %> — <%= account.name %>
                          </option>
                        <% end %>
                      </select>
                    </div>
                  </td>
                  <td class="px-3 py-2">
                    <input type="text" name={"lines[#{idx}][description]"} value={line["description"]}
                      placeholder="Optional note"
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
                  </td>
                  <td class="px-3 py-2">
                    <input type="number" name={"lines[#{idx}][debit]"} value={line["debit"]}
                      step="0.01" min="0" placeholder="0.00"
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-right text-sm font-mono text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
                  </td>
                  <td class="px-3 py-2">
                    <input type="number" name={"lines[#{idx}][credit]"} value={line["credit"]}
                      step="0.01" min="0" placeholder="0.00"
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-right text-sm font-mono text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10" />
                  </td>
                  <td class="px-3 py-2 text-center">
                    <button type="button" phx-click="remove_line" phx-value-index={idx}
                      class="text-gray-400 hover:text-red-500 text-xs">✕</button>
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot class="bg-gray-50 dark:bg-white/5">
              <tr>
                <td colspan="2" class="px-3 py-2 text-right text-xs font-semibold text-gray-500 uppercase tracking-wide">Totals</td>
                <td class={[
                  "px-3 py-2 text-right text-sm font-mono font-semibold",
                  if(balanced?(@lines), do: "text-emerald-600", else: "text-gray-900 dark:text-white")
                ]}>
                  <%= format_amount(total_debits(@lines)) %>
                </td>
                <td class={[
                  "px-3 py-2 text-right text-sm font-mono font-semibold",
                  if(balanced?(@lines), do: "text-emerald-600", else: "text-gray-900 dark:text-white")
                ]}>
                  <%= format_amount(total_credits(@lines)) %>
                </td>
                <td></td>
              </tr>
              <%= if !balanced?(@lines) && (Decimal.positive?(total_debits(@lines)) || Decimal.positive?(total_credits(@lines))) do %>
                <tr>
                  <td colspan="5" class="px-3 py-1 text-xs text-red-500 text-right">
                    Debits and credits must be equal and non-zero to post.
                  </td>
                </tr>
              <% end %>
            </tfoot>
          </table>
        </div>

        <div class="mb-6">
          <.button type="button" phx-click="add_line">
            + Add line
          </.button>
        </div>

        <div class="flex gap-3">
          <button type="submit" name="_action" value="draft"
            class="rounded-md bg-gray-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-gray-500">
            Save as Draft
          </button>
          <button type="submit" name="_action" value="post"
            disabled={!balanced?(@lines)}
            class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed dark:bg-emerald-500">
            Save & Post
          </button>
        </div>
      </form>
    </.page>
    """
  end
end
