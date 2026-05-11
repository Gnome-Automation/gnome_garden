defmodule GnomeGardenWeb.HealthController do
  use GnomeGardenWeb, :controller

  alias Ecto.Adapters.SQL
  alias GnomeGarden.Repo

  def show(conn, _params) do
    text(conn, "ok")
  end

  def ready(conn, _params) do
    checks = %{
      database: database_check(),
      document_storage: document_storage_check()
    }

    status =
      if ready?(checks) do
        :ok
      else
        :service_unavailable
      end

    conn
    |> put_status(status)
    |> json(%{
      status: status_label(status),
      checks: checks
    })
  end

  defp database_check do
    case SQL.query(Repo, "SELECT 1", [], timeout: 1_000, log: false) do
      {:ok, _result} -> %{status: "ok"}
      {:error, error} -> %{status: "error", message: Exception.message(error)}
    end
  end

  defp document_storage_check do
    cond do
      Application.get_env(:gnome_garden, :serve_local_storage?, false) ->
        %{status: "ok", mode: "local"}

      document_storage_service_configured?() ->
        %{status: "ok", mode: "external"}

      true ->
        %{status: "error", message: "document storage service is not configured"}
    end
  end

  defp document_storage_service_configured? do
    :gnome_garden
    |> Application.get_env(GnomeGarden.Acquisition.Document, [])
    |> Keyword.get(:storage, [])
    |> Keyword.has_key?(:service)
  end

  defp ready?(checks) do
    Enum.all?(checks, fn {_name, check} -> check.status == "ok" end)
  end

  defp status_label(:ok), do: "ok"
  defp status_label(:service_unavailable), do: "error"
end
