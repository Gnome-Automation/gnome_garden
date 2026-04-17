defmodule GnomeGarden.Agents.Tools.SaveProcurementSource do
  @moduledoc """
  Save a new procurement source to the database.

  Used by the SourceDiscovery agent to persist discovered procurement portals.
  """

  use Jido.Action,
    name: "save_procurement_source",
    description: "Save a newly discovered procurement source to the database",
    schema: [
      name: [type: :string, required: true, doc: "Name of the source (e.g., 'City of Irvine')"],
      url: [type: :string, required: true, doc: "URL of the procurement portal"],
      source_type: [type: :atom, required: true, doc: "Type: planetbids, opengov, sam_gov, etc."],
      portal_id: [type: :string, doc: "External portal ID if applicable"],
      region: [
        type: :atom,
        default: :socal,
        doc: "Region: oc, la, ie, sd, socal, norcal, ca, national"
      ],
      priority: [type: :atom, default: :medium, doc: "Priority: high, medium, low"],
      discovery_notes: [type: :string, doc: "How this source was discovered"]
    ]

  require Logger

  alias GnomeGarden.Agents.RunOutputLogger

  @impl true
  def run(params, context) do
    attrs = %{
      name: params.name,
      url: params.url,
      source_type: params.source_type,
      portal_id: Map.get(params, :portal_id),
      region: Map.get(params, :region, :socal),
      priority: Map.get(params, :priority, :medium),
      added_by: :agent,
      notes: Map.get(params, :discovery_notes),
      enabled: true
    }

    case Ash.create(GnomeGarden.Procurement.ProcurementSource, attrs) do
      {:ok, source} ->
        Logger.info(
          "[SaveProcurementSource] Created new procurement source: #{source.name} (#{source.url})"
        )
        log_output(context, :created, source)

        {:ok,
         %{
           id: source.id,
           name: source.name,
           url: source.url,
           source_type: source.source_type,
           message: "Successfully added procurement source: #{source.name}"
         }}

      {:error, %Ash.Error.Invalid{} = error} ->
        # Check if it's a uniqueness violation
        if String.contains?(inspect(error), "unique") do
          existing = existing_source(params.url)

          if existing do
            log_output(context, :existing, existing)
          end

          {:ok,
           %{
              name: params.name,
              url: params.url,
              id: existing && existing.id,
              already_exists: true,
              message: "Lead source already exists: #{params.url}"
            }}
        else
          {:error, "Failed to save procurement source: #{inspect(error)}"}
        end

      {:error, error} ->
        {:error, "Failed to save procurement source: #{inspect(error)}"}
    end
  end

  defp existing_source(url) do
    case Ash.read(GnomeGarden.Procurement.ProcurementSource, filter: [url: url]) do
      {:ok, [source | _]} -> source
      _ -> nil
    end
  end

  defp log_output(context, event, source) do
    RunOutputLogger.log(context, %{
      output_type: :procurement_source,
      output_id: source.id,
      event: event,
      label: source.name,
      summary: "#{event_label(event)} procurement source #{source.name}",
      metadata: %{
        url: source.url,
        source_type: source.source_type,
        region: source.region
      }
    })
  end

  defp event_label(:created), do: "Created"
  defp event_label(:existing), do: "Reused existing"
end
