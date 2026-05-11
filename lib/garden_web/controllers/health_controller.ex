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
    storage_config = document_storage_config()

    case Keyword.get(storage_config, :service) do
      {AshStorage.Service.S3, opts} ->
        s3_storage_check(opts)

      {AshStorage.Service.Test, _opts} ->
        %{status: "ok", mode: "test"}

      {AshStorage.Service.Disk, _opts} ->
        %{status: "ok", mode: "local"}

      {_service, _opts} ->
        %{status: "ok", mode: "configured"}

      nil ->
        fallback_storage_check()
    end
  end

  defp document_storage_config do
    :gnome_garden
    |> Application.get_env(GnomeGarden.Acquisition.Document, [])
    |> Keyword.get(:storage, [])
  end

  defp s3_storage_check(opts) do
    missing =
      [:bucket, :access_key_id, :secret_access_key]
      |> Enum.reject(&present_option?(opts, &1))

    if missing == [] do
      %{status: "ok", mode: "external", service: "s3"}
    else
      %{
        status: "error",
        mode: "external",
        service: "s3",
        message: "missing S3 storage options: #{Enum.join(missing, ", ")}"
      }
    end
  end

  defp fallback_storage_check do
    if Application.get_env(:gnome_garden, :serve_local_storage?, false) do
      %{status: "ok", mode: "local"}
    else
      %{status: "error", message: "document storage service is not configured"}
    end
  end

  defp present_option?(opts, key) do
    case Keyword.get(opts, key) do
      nil -> false
      "" -> false
      _value -> true
    end
  end

  defp ready?(checks) do
    Enum.all?(checks, fn {_name, check} -> check.status == "ok" end)
  end

  defp status_label(:ok), do: "ok"
  defp status_label(:service_unavailable), do: "error"
end
