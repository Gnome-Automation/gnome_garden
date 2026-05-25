defmodule GnomeGarden.Agents.Templates do
  @moduledoc """
  Registry of durable automation templates.

  The old Jido AI worker templates have been removed. Templates now point only
  at direct application workers that can be launched by `DeploymentRunner`
  through `execute_run/1`.
  """

  @templates %{
    "procurement_source_scan" => %{
      module: GnomeGarden.Agents.Workers.Procurement.SourceScan,
      description: "Runs a deterministic procurement scan for a single source through AshLua",
      model: :fast,
      max_iterations: 1
    }
  }

  @doc "Returns the config map for a named template."
  @spec get(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get(name) do
    case Map.get(@templates, name) do
      nil -> {:error, "Unknown template '#{name}'. Available: #{Enum.join(names(), ", ")}"}
      template -> {:ok, template}
    end
  end

  @doc "Returns all templates as a map keyed by name."
  @spec list() :: %{String.t() => map()}
  def list, do: @templates

  @doc "Returns all template names."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@templates)

  @doc "Returns true if a template with the given name exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(name), do: Map.has_key?(@templates, name)
end
