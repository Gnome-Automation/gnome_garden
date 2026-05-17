defmodule GnomeGardenWeb.InvoiceExportController do
  use GnomeGardenWeb, :controller

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.Invoice

  @exportable_statuses [:issued, :partial, :paid]

  plug :require_authenticated_user

  # Single invoice export
  def show(conn, %{"id" => id} = params) do
    format = Map.get(params, "format", "csv")

    case Finance.get_invoice(id, load: [:invoice_lines, :organization], authorize?: false) do
      {:ok, invoice} when invoice.status in @exportable_statuses ->
        case format do
          "csv" -> send_csv(conn, [invoice], filename: invoice.invoice_number)
          "pdf" -> render_pdf(conn, [invoice], title: invoice.invoice_number)
          _ -> redirect(conn, to: ~p"/finance/invoices/#{id}/review")
        end

      {:ok, _invoice} ->
        conn
        |> put_flash(:error, "Only issued, partial, or paid invoices can be exported.")
        |> redirect(to: ~p"/finance/invoices/#{id}/review")

      {:error, _} ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  # Batch export
  def batch(conn, params) do
    format = Map.get(params, "format", "csv")

    with {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]) do
      invoices = query_invoices(from, to, params["organization_id"])
      filename = "invoices-#{params["from"]}-to-#{params["to"]}"

      case format do
        "pdf" -> render_pdf(conn, invoices, title: filename)
        _ -> send_csv(conn, invoices, filename: filename)
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Please provide a valid date range (from and to are required).")
        |> redirect(to: ~p"/finance/invoices")
    end
  end

  # --- Private ---

  defp query_invoices(from, to, org_id) do
    Invoice
    |> Ash.Query.filter(status in ^@exportable_statuses)
    |> Ash.Query.filter(not is_nil(issued_on) and issued_on >= ^from and issued_on <= ^to)
    |> then(fn q ->
      if org_id && org_id != "" do
        Ash.Query.filter(q, organization_id == ^org_id)
      else
        q
      end
    end)
    |> Ash.Query.load([:invoice_lines, :organization])
    |> Ash.Query.sort(issued_on: :asc, invoice_number: :asc)
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp send_csv(conn, invoices, opts) do
    raw_filename = Keyword.get(opts, :filename, "invoices")
    safe_filename = String.replace(raw_filename, ~r/[^\w\-.]/, "_") <> ".csv"
    csv = build_csv(invoices)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{safe_filename}"])
    |> send_resp(200, csv)
  end

  defp render_pdf(conn, invoices, opts) do
    title = Keyword.get(opts, :title, "invoices")
    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    # put_layout(false) suppresses the app shell — the PDF template is a
    # standalone HTML document with its own <head>/<body> and print CSS.
    conn
    |> put_layout(false)
    |> render(:invoice_pdf,
      invoices: invoices,
      title: title,
      mercury_info: mercury_info,
      company_name: company_name
    )
  end

  defp build_csv(invoices) do
    header = "invoice_number,issued_date,due_date,client,description,quantity,unit_price,line_total,invoice_total,status,currency\n"

    rows =
      Enum.flat_map(invoices, fn invoice ->
        client = (invoice.organization && invoice.organization.name) || ""

        lines =
          if invoice.invoice_lines == [] do
            # Invoice with no lines — emit one row with blank line fields
            [
              [
                csv_escape(invoice.invoice_number),
                to_string(invoice.issued_on || ""),
                to_string(invoice.due_on || ""),
                csv_escape(client),
                "",
                "",
                "",
                "",
                decimal_str(invoice.total_amount),
                to_string(invoice.status),
                invoice.currency_code
              ]
              |> Enum.join(",")
            ]
          else
            Enum.map(invoice.invoice_lines, fn line ->
              [
                csv_escape(invoice.invoice_number),
                to_string(invoice.issued_on || ""),
                to_string(invoice.due_on || ""),
                csv_escape(client),
                csv_escape(line.description),
                decimal_str(line.quantity),
                decimal_str(line.unit_price),
                decimal_str(line.line_total),
                decimal_str(invoice.total_amount),
                to_string(invoice.status),
                invoice.currency_code
              ]
              |> Enum.join(",")
            end)
          end

        lines
      end)

    header <> Enum.join(rows, "\n") <> "\n"
  end

  defp decimal_str(nil), do: ""
  defp decimal_str(d), do: Decimal.to_string(d)

  defp csv_escape(nil), do: ""

  defp csv_escape(str) do
    # Prevent CSV formula injection — prefix formula-starting chars with a tab
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

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] || conn.assigns[:current_client_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
