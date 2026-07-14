defmodule GnomeGarden.Procurement.Changes.InitializeSourceGovernance do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    source_type = Ash.Changeset.get_attribute(changeset, :source_type)
    name = Ash.Changeset.get_attribute(changeset, :name)

    changeset
    |> Ash.Changeset.force_change_attribute(:allowed_retrieval_paths, paths(source_type))
    |> Ash.Changeset.force_change_attribute(:adapter_owner, adapter_owner(source_type))
    |> Ash.Changeset.force_change_attribute(
      :expected_coverage,
      "Opportunities published through #{name || "this source"}"
    )
    |> Ash.Changeset.force_change_attribute(:launch_prerequisites, prerequisites(source_type))
  end

  defp paths(:sam_gov), do: [:provider_api]
  defp paths(:opengov), do: [:provider_api, :http, :browser]
  defp paths(:planetbids), do: [:provider_api, :browser]
  defp paths(:bidnet), do: [:playwright]
  defp paths(:company_site), do: [:browser]
  defp paths(_source_type), do: [:http, :browser]

  defp adapter_owner(:sam_gov), do: "GnomeGarden.Agents.Procurement.SamGovScanner"
  defp adapter_owner(:opengov), do: "GnomeGarden.Agents.Procurement.OpenGovAdapter"
  defp adapter_owner(:planetbids), do: "GnomeGarden.Agents.Tools.Procurement.ScanPlanetBids"
  defp adapter_owner(:bidnet), do: "GnomeGarden.Procurement.BidNetProvider"
  defp adapter_owner(_source_type), do: "GnomeGarden.Agents.Procurement.ListingScanner"

  defp prerequisites(:sam_gov), do: ["verified SAM.gov API key"]
  defp prerequisites(:bidnet), do: ["verified provider credential", "valid browser session"]
  defp prerequisites(_source_type), do: []
end
