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
