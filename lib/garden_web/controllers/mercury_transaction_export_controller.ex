defmodule GnomeGardenWeb.MercuryTransactionExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Mercury
  alias GnomeGarden.Mercury.Transaction

  plug :require_authenticated

  # GET /finance/mercury/batch-export?from=&to=&status_filter=&kind=&format=csv|pdf
  def batch(conn, params) do
    format = Map.get(params, "format", "csv")

    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      transactions = query_transactions(from, to, params["status_filter"], params["kind"])
      filename = "mercury-transactions-#{params["from"]}-to-#{params["to"]}"

      case format do
        "pdf" -> render_pdf(conn, transactions, title: filename)
        _ -> send_csv(conn, transactions, filename: filename)
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Please provide a valid date range.")
        |> redirect(to: ~p"/finance/mercury")
    end
  end

  # GET /finance/mercury/transactions/:id/export?format=csv|pdf
  def show(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "csv")

    case Ash.get(Transaction, id, domain: Mercury, authorize?: false) do
      {:ok, txn} ->
        filename = "mercury-#{txn.mercury_id || txn.id}"

        case format do
          "pdf" -> render_pdf(conn, [txn], title: filename)
          _ -> send_csv(conn, [txn], filename: filename)
        end

      {:error, _} ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  # --- Private ---

  defp query_transactions(from, to, status_filter, kind) do
    # +1 day on `to` makes the range inclusive of the selected end date,
    # matching the same offset applied in MercuryLive.handle_event("filter_changed", ...)
    from_dt = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    to_dt = DateTime.new!(Date.add(to, 1), ~T[00:00:00], "Etc/UTC")
    zero = Decimal.new("0")

    query =
      Transaction
      |> Ash.Query.filter(occurred_at >= ^from_dt)
      |> Ash.Query.filter(occurred_at < ^to_dt)
      |> Ash.Query.sort(occurred_at: :asc)

    query =
      case status_filter do
        "matched" ->
          Ash.Query.filter(query, match_confidence in [:exact, :probable, :possible])

        "unmatched" ->
          Ash.Query.filter(
            query,
            (is_nil(match_confidence) or match_confidence == :unmatched) and status != :pending
          )

        "pending" ->
          Ash.Query.filter(query, status == :pending)

        _ ->
          query
      end

    query =
      case kind do
        "inbound" -> Ash.Query.filter(query, amount > ^zero)
        "outbound" -> Ash.Query.filter(query, amount < ^zero)
        _ -> query
      end

    Ash.read!(query, domain: Mercury, authorize?: false)
  end

  defp send_csv(conn, transactions, opts) do
    raw_filename = Keyword.get(opts, :filename, "mercury-transactions")
    safe_filename = String.replace(raw_filename, ~r/[^\w\-.]/, "_") <> ".csv"
    csv = build_csv(transactions)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{safe_filename}"])
    |> send_resp(200, csv)
  end

  defp render_pdf(conn, transactions, opts) do
    title = Keyword.get(opts, :title, "mercury-transactions")
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    conn
    |> put_layout(false)
    |> render(:transaction_pdf,
      transactions: transactions,
      title: title,
      company_name: company_name
    )
  end

  defp build_csv(transactions) do
    header =
      "occurred_at,counterparty,amount,kind,direction,status,match_status,reconciliation_category,reconciliation_note,mercury_id\n"

    rows =
      Enum.map(transactions, fn txn ->
        direction =
          if Decimal.compare(txn.amount, Decimal.new("0")) == :gt, do: "inbound", else: "outbound"

        occurred_at =
          if txn.occurred_at, do: to_string(DateTime.to_date(txn.occurred_at)), else: ""

        [
          occurred_at,
          csv_escape(txn.counterparty_name || txn.bank_description || ""),
          decimal_str(txn.amount),
          to_string(txn.kind || ""),
          direction,
          to_string(txn.status || ""),
          to_string(txn.match_confidence || "unmatched"),
          to_string(txn.reconciliation_category || ""),
          csv_escape(txn.reconciliation_note || ""),
          txn.mercury_id || ""
        ]
        |> Enum.join(",")
      end)

    header <> Enum.join(rows, "\n") <> "\n"
  end

  defp decimal_str(nil), do: ""
  defp decimal_str(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)

  defp csv_escape(nil), do: ""

  defp csv_escape(str) do
    str =
      if String.match?(str, ~r/^[=+\-@\t\r]/) do
        "\t" <> str
      else
        str
      end

    if String.contains?(str, [",", "\"", "\n"]) do
      ~s["#{String.replace(str, "\"", "\"\"")}"]
    else
      str
    end
  end

  defp parse_date(nil), do: {:error, :missing}
  defp parse_date(""), do: {:error, :missing}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid}
    end
  end

  defp require_authenticated(conn, _opts) do
    if conn.assigns[:current_user] || conn.assigns[:current_client_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
