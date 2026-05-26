defmodule GnomeGardenWeb.PaymentsExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Payment

  plug :require_authenticated

  # Staff batch export: GET /finance/payments/batch-export?from=&to=&organization_id=&format=csv|pdf
  def batch(conn, params) do
    format = Map.get(params, "format", "csv")

    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      payments = query_payments(from, to, params["organization_id"])
      filename = "payments-#{params["from"]}-to-#{params["to"]}"

      case format do
        "pdf" -> render_pdf(conn, payments, title: filename)
        _ -> send_csv(conn, payments, filename: filename)
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Please provide a valid date range.")
        |> redirect(to: ~p"/finance/payments")
    end
  end

  # Single payment export: GET /finance/payments/:id/export?format=csv|pdf
  def show(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "csv")

    case Ash.get(Payment, id,
           domain: Finance,
           load: [:organization, applications: [:invoice]],
           authorize?: false
         ) do
      {:ok, payment} ->
        case format do
          "pdf" -> render_pdf(conn, [payment], title: payment.payment_number)
          _ -> send_csv(conn, [payment], filename: payment.payment_number)
        end

      {:error, _} ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  # Portal batch export: GET /portal/payments/export?from=&to=&format=csv|pdf
  def portal(conn, params) do
    actor = conn.assigns[:current_client_user]
    format = Map.get(params, "format", "csv")

    payments =
      case Finance.list_portal_payments(actor: actor) do
        {:ok, list} -> filter_by_date(list, params["from"], params["to"])
        _ -> []
      end

    case format do
      "pdf" -> render_pdf(conn, payments, title: "my-payment-history")
      _ -> send_csv(conn, payments, filename: "my-payment-history")
    end
  end

  # Portal single payment export: GET /portal/payments/:id/export?format=csv|pdf
  def portal_show(conn, %{"id" => id} = params) do
    actor = conn.assigns[:current_client_user]
    format = Map.get(params, "format", "csv")

    case Ash.get(Payment, id,
           domain: Finance,
           load: [:organization, applications: [:invoice]],
           authorize?: false
         ) do
      {:ok, payment} when payment.organization_id == actor.organization_id ->
        case format do
          "pdf" -> render_pdf(conn, [payment], title: payment.payment_number)
          _ -> send_csv(conn, [payment], filename: payment.payment_number)
        end

      _ ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  # --- Private ---

  defp query_payments(from, to, org_id) do
    Payment
    |> Ash.Query.filter(received_on >= ^from and received_on <= ^to)
    |> then(fn q ->
      if org_id && org_id != "" do
        Ash.Query.filter(q, organization_id == ^org_id)
      else
        q
      end
    end)
    |> Ash.Query.load([:organization, applications: [:invoice]])
    |> Ash.Query.sort(received_on: :asc, inserted_at: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp send_csv(conn, payments, opts) do
    raw_filename = Keyword.get(opts, :filename, "payments")
    safe_filename = String.replace(raw_filename, ~r/[^\w\-.]/, "_") <> ".csv"
    csv = build_csv(payments)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{safe_filename}"])
    |> send_resp(200, csv)
  end

  defp render_pdf(conn, payments, opts) do
    title = Keyword.get(opts, :title, "payments")
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    conn
    |> put_layout(false)
    |> render(:payment_pdf,
      payments: payments,
      title: title,
      company_name: company_name
    )
  end

  defp build_csv(payments) do
    header = "payment_number,received_on,method,amount,currency,reference,applied_to_invoices,client\n"

    rows =
      Enum.map(payments, fn payment ->
        client =
          if is_struct(payment.organization, GnomeGarden.Operations.Organization),
            do: csv_escape(payment.organization.name),
            else: ""

        invoice_numbers =
          (payment.applications || [])
          |> Enum.map(fn app -> app.invoice && app.invoice.invoice_number end)
          |> Enum.reject(&is_nil/1)
          |> Enum.join("; ")

        [
          csv_escape(payment.payment_number || ""),
          to_string(payment.received_on || ""),
          to_string(payment.payment_method || ""),
          decimal_str(payment.amount),
          payment.currency_code || "USD",
          csv_escape(payment.reference || ""),
          csv_escape(invoice_numbers),
          client
        ]
        |> Enum.join(",")
      end)

    header <> Enum.join(rows, "\n") <> "\n"
  end

  defp decimal_str(nil), do: ""
  defp decimal_str(d), do: Decimal.to_string(Decimal.round(d, 2))

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

  defp filter_by_date(payments, from_str, to_str) do
    from = parse_date_optional(from_str)
    to = parse_date_optional(to_str)

    payments
    |> then(fn list ->
      if from, do: Enum.filter(list, &(&1.received_on == nil or Date.compare(&1.received_on, from) != :lt)), else: list
    end)
    |> then(fn list ->
      if to, do: Enum.filter(list, &(&1.received_on == nil or Date.compare(&1.received_on, to) != :gt)), else: list
    end)
  end

  defp parse_date_optional(nil), do: nil
  defp parse_date_optional(""), do: nil
  defp parse_date_optional(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
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
