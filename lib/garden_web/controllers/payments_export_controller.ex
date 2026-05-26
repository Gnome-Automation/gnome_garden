defmodule GnomeGardenWeb.PaymentsExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Payment

  plug :require_authenticated

  # Staff: GET /finance/payments/export
  def staff(conn, _params) do
    payments =
      Payment
      |> Ash.Query.load([:organization, applications: [:invoice]])
      |> Ash.Query.sort(received_on: :desc, inserted_at: :desc)
      |> Ash.read!(domain: Finance, authorize?: false)

    send_csv(conn, payments, "payments-export")
  end

  # Portal: GET /portal/payments/export
  def portal(conn, _params) do
    actor = conn.assigns[:current_client_user]

    payments =
      case Finance.list_portal_payments(actor: actor) do
        {:ok, payments} -> payments
        _ -> []
      end

    send_csv(conn, payments, "my-payment-history")
  end

  defp send_csv(conn, payments, filename) do
    safe_filename = "#{filename}.csv"
    csv = build_csv(payments)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{safe_filename}"])
    |> send_resp(200, csv)
  end

  defp build_csv(payments) do
    header = "payment_number,received_on,method,amount,currency,reference,applied_to_invoices,client\n"

    rows =
      Enum.map(payments, fn payment ->
        client =
          cond do
            Map.has_key?(payment, :organization) && payment.organization ->
              csv_escape(payment.organization.name)
            true ->
              ""
          end

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
