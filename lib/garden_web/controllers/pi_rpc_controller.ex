defmodule GnomeGardenWeb.PiRpcController do
  @moduledoc """
  HTTP receiver for the pi sidecar.

  Pi extensions POST `{"action": "...", "input": {...}}` to persist findings.
  Only actions in the `@actions` allowlist can be invoked. Auth is enforced
  upstream by `GnomeGardenWeb.Plugs.PiServiceAuth`.

  Responses are uniform:

      {"success": true,  "data": {"id": "..."}}
      {"success": false, "errors": [%{type, field, message}, ...]}

  The structured error shape lets the sidecar dead-letter queue retry
  cleanly and lets the LLM correct itself on the next prompt.
  """
  use GnomeGardenWeb, :controller

  require Logger

  alias GnomeGarden.Acquisition.PiRpcDispatcher
  alias GnomeGarden.Acquisition.PiRpcErrors

  def run(conn, %{"action" => action, "input" => input})
      when is_binary(action) and is_map(input) do
    case PiRpcDispatcher.dispatch(action, input) do
      {:ok, record} ->
        json(conn, %{success: true, data: %{id: record.id}})

      {:error, {:unknown_action, _}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          errors: [%{type: "unknown_action", field: nil, message: "unknown action: #{action}"}]
        })

      {:error, error} ->
        errors = PiRpcErrors.format(error)
        Logger.warning("Pi RPC #{action} failed: #{inspect(errors)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, errors: errors})
    end
  end

  def run(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      errors: [%{type: "bad_request", field: nil, message: "expected: {action, input}"}]
    })
  end
end
