defmodule GnomeHub.Agents.Tools.SaveLeadSource do
  @moduledoc """
  Save a new lead source to the database.

  Used by the SourceDiscovery agent to persist discovered procurement portals.
  """

  use Jido.Action,
    name: "save_lead_source",
    description: "Save a newly discovered lead source to the database",
    schema: [
      name: [type: :string, required: true, doc: "Name of the source (e.g., 'City of Irvine')"],
      url: [type: :string, required: true, doc: "URL of the procurement portal"],
      source_type: [type: :atom, required: true, doc: "Type: planetbids, opengov, sam_gov, etc."],
      portal_id: [type: :string, doc: "External portal ID if applicable"],
      region: [type: :atom, default: :socal, doc: "Region: oc, la, ie, sd, socal, norcal, ca, national"],
      priority: [type: :atom, default: :medium, doc: "Priority: high, medium, low"],
      discovery_notes: [type: :string, doc: "How this source was discovered"]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    attrs = %{
      name: params.name,
      url: params.url,
      source_type: params.source_type,
      portal_id: Map.get(params, :portal_id),
      region: Map.get(params, :region, :socal),
      priority: Map.get(params, :priority, :medium),
      discovered_by: :agent,
      discovery_notes: Map.get(params, :discovery_notes),
      enabled: true
    }

    case Ash.create(GnomeHub.Agents.LeadSource, attrs) do
      {:ok, source} ->
        Logger.info("[SaveLeadSource] Created new lead source: #{source.name} (#{source.url})")
        {:ok, %{
          id: source.id,
          name: source.name,
          url: source.url,
          source_type: source.source_type,
          message: "Successfully added lead source: #{source.name}"
        }}

      {:error, %Ash.Error.Invalid{} = error} ->
        # Check if it's a uniqueness violation
        if String.contains?(inspect(error), "unique") do
          {:ok, %{
            name: params.name,
            url: params.url,
            already_exists: true,
            message: "Lead source already exists: #{params.url}"
          }}
        else
          {:error, "Failed to save lead source: #{inspect(error)}"}
        end

      {:error, error} ->
        {:error, "Failed to save lead source: #{inspect(error)}"}
    end
  end
end
