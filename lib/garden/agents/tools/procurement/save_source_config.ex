defmodule GnomeGarden.Agents.Tools.Procurement.SaveSourceConfig do
  @moduledoc """
  Save discovered scraping configuration for a procurement source.

  This helper is used by deterministic source bootstrap paths after they
  identify a reliable listing pattern.
  The saved config allows future scans to be deterministic (no LLM needed).
  """

  def run(params, _context) do
    scrape_config = %{
      listing_url: params.listing_url,
      listing_selector: params.listing_selector,
      title_selector: params.title_selector,
      date_selector: params[:date_selector],
      link_selector: params[:link_selector],
      description_selector: params[:description_selector],
      agency_selector: params[:agency_selector],
      pagination: %{
        type: params[:pagination_type] || "none",
        selector: params[:pagination_selector]
      },
      search_selector: params[:search_selector],
      notes: params[:notes]
    }

    case GnomeGarden.Procurement.get_procurement_source(params.procurement_source_id) do
      {:ok, source} ->
        case GnomeGarden.Procurement.configure_procurement_source(source, %{
               scrape_config: scrape_config
             }) do
          {:ok, updated} ->
            {:ok,
             %{
               saved: true,
               procurement_source_id: updated.id,
               name: updated.name,
               config_status: :configured,
               message:
                 "Scraping config saved! Future scans will use deterministic scraping (no LLM)."
             }}

          {:error, error} ->
            {:error, "Failed to save source config: #{inspect(error)}"}
        end

      {:error, _} ->
        {:error, "Procurement source not found: #{params.procurement_source_id}"}
    end
  end
end
