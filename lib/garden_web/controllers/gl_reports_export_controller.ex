defmodule GnomeGardenWeb.GlReportsExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.{ChartOfAccount, JournalEntryLine}

  plug :require_authenticated_user

  # GET /finance/reports/profit-loss/export?from=YYYY-MM-DD&to=YYYY-MM-DD
  def profit_loss(conn, params) do
    from = parse_date(params["from"])
    to = parse_date(params["to"])
    today = Date.utc_today()
    from_label = params["from"] || ""
    to_label = params["to"] || ""

    accounts =
      ChartOfAccount
      |> Ash.Query.filter(type in [:revenue, :expense])
      |> Ash.Query.sort(number: :asc)
      |> Ash.read!(domain: Finance, authorize?: false)

    rows =
      Enum.map(accounts, fn acct ->
        balance = account_balance_period(acct, from, to)
        %{number: acct.number, name: acct.name, type: acct.type, balance: balance}
      end)

    header = "type,account_number,account_name,amount\n"

    csv_rows =
      rows
      |> Enum.reject(fn r -> Decimal.equal?(r.balance, Decimal.new("0")) end)
      |> Enum.map(fn r ->
        [
          csv_escape(to_string(r.type)),
          to_string(r.number),
          csv_escape(r.name),
          decimal_str(r.balance)
        ]
        |> Enum.join(",")
      end)

    csv = header <> Enum.join(csv_rows, "\n") <> "\n"
    filename = "profit-loss-#{from_label}-#{to_label}-#{today}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
    |> send_resp(200, csv)
  end

  # GET /finance/reports/balance-sheet/export?as_of=YYYY-MM-DD
  def balance_sheet(conn, params) do
    as_of = parse_date(params["as_of"])
    today = Date.utc_today()
    as_of_label = params["as_of"] || to_string(today)

    accounts =
      ChartOfAccount
      |> Ash.Query.filter(type in [:asset, :liability, :equity])
      |> Ash.Query.sort(number: :asc)
      |> Ash.read!(domain: Finance, authorize?: false)

    rows =
      Enum.map(accounts, fn acct ->
        balance = account_balance_as_of(acct, as_of)
        %{number: acct.number, name: acct.name, type: acct.type, balance: balance}
      end)

    header = "type,account_number,account_name,balance\n"

    csv_rows =
      rows
      |> Enum.reject(fn r -> Decimal.equal?(r.balance, Decimal.new("0")) end)
      |> Enum.map(fn r ->
        [
          csv_escape(to_string(r.type)),
          to_string(r.number),
          csv_escape(r.name),
          decimal_str(r.balance)
        ]
        |> Enum.join(",")
      end)

    csv = header <> Enum.join(csv_rows, "\n") <> "\n"
    filename = "balance-sheet-#{as_of_label}-#{today}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
    |> send_resp(200, csv)
  end

  # GET /finance/reports/gl-detail/export?account_id=UUID&from=YYYY-MM-DD&to=YYYY-MM-DD
  def gl_detail(conn, params) do
    account_id = params["account_id"] || ""
    from = parse_date(params["from"])
    to = parse_date(params["to"])
    today = Date.utc_today()

    {account_number, lines} =
      if account_id != "" do
        case Ash.get(ChartOfAccount, account_id, domain: Finance, authorize?: false) do
          {:ok, acct} ->
            lines = load_lines(account_id, from, to)
            {acct.number, lines}

          _ ->
            {"unknown", []}
        end
      else
        {"all", []}
      end

    header = "entry_number,date,description,debit,credit\n"

    csv_rows =
      Enum.map(lines, fn line ->
        [
          csv_escape(line.journal_entry.entry_number),
          to_string(line.journal_entry.date),
          csv_escape(line.description || line.journal_entry.description),
          if(line.debit, do: decimal_str(line.debit), else: ""),
          if(line.credit, do: decimal_str(line.credit), else: "")
        ]
        |> Enum.join(",")
      end)

    csv = header <> Enum.join(csv_rows, "\n") <> "\n"
    filename = "gl-detail-#{account_number}-#{today}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
    |> send_resp(200, csv)
  end

  # --- Private ---

  defp account_balance_period(account, from, to) do
    q =
      JournalEntryLine
      |> Ash.Query.filter(account_id == ^account.id)
      |> Ash.Query.filter(journal_entry.status == :posted)
      |> Ash.Query.load([:journal_entry])

    q = if from, do: Ash.Query.filter(q, journal_entry.date >= ^from), else: q
    q = if to, do: Ash.Query.filter(q, journal_entry.date <= ^to), else: q

    compute_balance(Ash.read!(q, domain: Finance, authorize?: false), account.normal_balance)
  end

  defp account_balance_as_of(account, as_of) do
    q =
      JournalEntryLine
      |> Ash.Query.filter(account_id == ^account.id)
      |> Ash.Query.filter(journal_entry.status == :posted)
      |> Ash.Query.load([:journal_entry])

    q = if as_of, do: Ash.Query.filter(q, journal_entry.date <= ^as_of), else: q

    compute_balance(Ash.read!(q, domain: Finance, authorize?: false), account.normal_balance)
  end

  defp load_lines(account_id, from, to) do
    q =
      JournalEntryLine
      |> Ash.Query.filter(account_id == ^account_id)
      |> Ash.Query.filter(journal_entry.status == :posted)
      |> Ash.Query.load([:journal_entry])
      |> Ash.Query.sort(inserted_at: :asc)

    q = if from, do: Ash.Query.filter(q, journal_entry.date >= ^from), else: q
    q = if to, do: Ash.Query.filter(q, journal_entry.date <= ^to), else: q

    Ash.read!(q, domain: Finance, authorize?: false)
  end

  defp compute_balance(lines, normal_balance) do
    debits =
      lines
      |> Enum.map(& &1.debit)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    credits =
      lines
      |> Enum.map(& &1.credit)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    case normal_balance do
      :debit -> Decimal.sub(debits, credits)
      :credit -> Decimal.sub(credits, debits)
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp decimal_str(nil), do: ""
  defp decimal_str(d), do: Decimal.to_string(Decimal.round(d, 2))

  defp csv_escape(nil), do: ""

  defp csv_escape(str) do
    str = to_string(str)

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

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
