defmodule GnomeGarden.Calculations.AcquisitionProgramRunnable do
  @moduledoc false

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:discovery_program_id, :metadata, :program_family, :status]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &runnable?/1)
  end

  defp runnable?(program) do
    program.status == :active and routed?(program)
  end

  defp routed?(program) do
    is_binary(program.discovery_program_id) or
      metadata_route?(program.metadata) or
      not is_nil(default_deployment_name(program))
  end

  defp metadata_route?(metadata) when is_map(metadata) do
    Enum.any?(
      ["agent_deployment_id", "agent_deployment_name", "agent_template"],
      &(metadata_value(metadata, &1) not in [nil, ""])
    )
  end

  defp metadata_route?(_metadata), do: false

  defp metadata_value(metadata, "agent_deployment_id"),
    do: Map.get(metadata, "agent_deployment_id") || Map.get(metadata, :agent_deployment_id)

  defp metadata_value(metadata, "agent_deployment_name"),
    do: Map.get(metadata, "agent_deployment_name") || Map.get(metadata, :agent_deployment_name)

  defp metadata_value(metadata, "agent_template"),
    do: Map.get(metadata, "agent_template") || Map.get(metadata, :agent_template)

  defp default_deployment_name(%{program_family: :discovery}), do: "Commercial Target Discovery"
  defp default_deployment_name(%{program_family: :procurement}), do: "SoCal Source Discovery"
  defp default_deployment_name(_program), do: nil
end
