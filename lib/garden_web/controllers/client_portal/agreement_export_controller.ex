defmodule GnomeGardenWeb.ClientPortal.AgreementExportController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Commercial

  plug :require_client_user

  def show(conn, %{"id" => id}) do
    actor = conn.assigns.current_client_user
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")

    case Commercial.get_portal_agreement(id, actor: actor) do
      {:ok, agreement} ->
        conn
        |> put_layout(false)
        |> render(:agreement_pdf,
          agreement: agreement,
          company_name: company_name
        )

      {:error, _} ->
        conn
        |> put_status(404)
        |> put_view(html: GnomeGardenWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  def batch(conn, params) do
    actor = conn.assigns.current_client_user
    company_name = Application.get_env(:gnome_garden, :company_name, "Gnome Automation")
    format = Map.get(params, "format", "pdf")

    agreements =
      case Commercial.list_portal_agreements(actor: actor) do
        {:ok, list} -> filter_by_date(list, params["from"], params["to"])
        _ -> []
      end

    case format do
      "csv" ->
        csv = build_csv(agreements)
        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s[attachment; filename="agreements-export.csv"])
        |> send_resp(200, csv)

      _ ->
        conn
        |> put_layout(false)
        |> render(:agreements_batch_pdf, agreements: agreements, company_name: company_name)
    end
  end

  defp filter_by_date(agreements, from_str, to_str) do
    from = parse_date(from_str)
    to = parse_date(to_str)

    agreements
    |> then(fn list ->
      if from, do: Enum.filter(list, &(&1.start_on == nil or Date.compare(&1.start_on, from) != :lt)), else: list
    end)
    |> then(fn list ->
      if to, do: Enum.filter(list, &(&1.start_on == nil or Date.compare(&1.start_on, to) != :gt)), else: list
    end)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp build_csv(agreements) do
    header = "name,type,billing_model,status,start_on,end_on,contract_value\n"

    rows =
      Enum.map(agreements, fn ag ->
        [
          csv_escape(ag.name),
          to_string(ag.agreement_type || ""),
          ag.billing_model |> to_string() |> String.replace("_", " "),
          to_string(ag.status || ""),
          to_string(ag.start_on || ""),
          to_string(ag.end_on || ""),
          if(ag.contract_value, do: Decimal.to_string(ag.contract_value), else: "")
        ]
        |> Enum.join(",")
      end)

    header <> Enum.join(rows, "\n") <> "\n"
  end

  defp csv_escape(nil), do: ""
  defp csv_escape(str) do
    if String.contains?(str, [",", "\"", "\n"]),
      do: ~s["#{String.replace(str, "\"", "\"\"")}"],
      else: str
  end

  defp require_client_user(conn, _opts) do
    if conn.assigns[:current_client_user] do
      conn
    else
      conn
      |> redirect(to: ~p"/portal/login")
      |> halt()
    end
  end
end
