defmodule GnomeGarden.Acquisition.PiRpcDispatcher do
  @moduledoc """
  Shared dispatcher for the pi RPC action allowlist.

  Used by both `GnomeGardenWeb.PiRpcController` (live HTTP requests from the
  sidecar) and `GnomeGarden.Acquisition.Workers.RetryFailedImports` (replaying
  dead-lettered payloads). Keeping the action map in one place means the two
  paths can never drift.
  """

  @actions %{
    "save_bid" => {GnomeGarden.Procurement, :create_bid},
    "save_source" => {GnomeGarden.Procurement, :create_procurement_source},
    "save_organization" => {GnomeGarden.Operations, :create_organization},
    "save_discovery_record" => {GnomeGarden.Commercial, :create_discovery_record},
    "save_target" => {GnomeGarden.Commercial, :create_prospect_discovery_record},
    "save_opportunity" => {GnomeGarden.Commercial, :create_opportunity_discovery_record},
    "save_source_config" => {GnomeGarden.Procurement, :save_source_config},
    "run_source_scan" => {GnomeGarden.Procurement, :run_source_scan}
  }

  @doc "Returns the configured action map (action name → {Module, function})."
  @spec actions() :: %{String.t() => {module(), atom()}}
  def actions, do: @actions

  @doc """
  Dispatches an action by name with the given input map.

  Returns `{:ok, record}` or `{:error, reason}`. Use the controller's
  `format_errors/1` to render `{:error, _}` for HTTP responses.
  """
  @spec dispatch(String.t(), map()) :: {:ok, struct()} | {:error, term()}
  def dispatch(action, input) when is_binary(action) and is_map(input) do
    case Map.fetch(@actions, action) do
      {:ok, {mod, fun}} -> apply(mod, fun, [input])
      :error -> {:error, {:unknown_action, action}}
    end
  end
end
