defmodule GnomeGardenWeb.ArAgingExportController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Finance

  plug :require_authenticated_user

  def export(conn, params) do
    actor = conn.assigns.current_user
    format = Map.get(params, "format", "csv")
    show_all = params["show_all"] == "true"
    org_id = Map.get(params, "org_id", "")

    invoices = load_invoices(actor, show_all: show_all, org_id: org_id)
    bucketed = bucket_invoices(invoices)
    today = Date.utc_today()
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    case format do
      "pdf" ->
        conn
        |> put_layout(false)
        |> render(:ar_aging_pdf,
          bucketed: bucketed,
          buckets: buckets(),
          grand_total: compute_grand_total(invoices),
          today: today,
          company_name: company_name
        )

      _ ->
        csv = build_csv(bucketed, today)

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s[attachment; filename="ar-aging-#{today}.csv"])
        |> send_resp(200, csv)
    end
  end

  # --- Private ---

  defp load_invoices(actor, opts) do
    show_all = Keyword.get(opts, :show_all, false)
    org_id = Keyword.get(opts, :org_id, "")

    invoices =
      if show_all do
        case Finance.list_invoices(
               actor: actor,
               query: [
                 sort: [due_on: :asc, inserted_at: :desc],
                 load: [:status_variant, organization: []]
               ]
             ) do
          {:ok, list} -> list
          _ -> []
        end
      else
        case Finance.list_open_invoices(
               actor: actor,
               query: [load: [:status_variant, organization: []]]
             ) do
          {:ok, list} -> list
          _ -> []
        end
      end

    if org_id && org_id != "" do
      Enum.filter(invoices, &(to_string(&1.organization_id) == org_id))
    else
      invoices
    end
  end

  defp bucket_invoices(invoices) do
    today = Date.utc_today()

    Enum.group_by(invoices, fn inv ->
      days = if inv.due_on, do: Date.diff(today, inv.due_on), else: 0

      cond do
        days <= 0 -> :current
        days <= 30 -> :days_1_30
        days <= 60 -> :days_31_60
        days <= 90 -> :days_61_90
        true -> :days_91_plus
      end
    end)
  end

  defp buckets do
    [
      {:current, "Current"},
      {:days_1_30, "1-30 days"},
      {:days_31_60, "31-60 days"},
      {:days_61_90, "61-90 days"},
      {:days_91_plus, "90+ days"}
    ]
  end

  defp compute_grand_total(invoices) do
    invoices
    |> Enum.filter(&(&1.status in [:issued, :partial]))
    |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
      Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
    end)
  end

  defp build_csv(bucketed, today) do
    header = "bucket,invoice_number,client,issued_date,due_date,days_overdue,balance_due,status\n"

    rows =
      Enum.flat_map(buckets(), fn {key, label} ->
        bucket = Map.get(bucketed, key, [])

        Enum.map(bucket, fn inv ->
          days =
            if inv.due_on do
              d = Date.diff(today, inv.due_on)
              if d > 0, do: to_string(d), else: "0"
            else
              "—"
            end

          [
            csv_escape(label),
            csv_escape(inv.invoice_number),
            csv_escape((inv.organization && inv.organization.name) || ""),
            to_string(inv.issued_on || ""),
            to_string(inv.due_on || ""),
            days,
            decimal_str(inv.balance_amount),
            to_string(inv.status)
          ]
          |> Enum.join(",")
        end)
      end)

    header <> Enum.join(rows, "\n") <> "\n"
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
