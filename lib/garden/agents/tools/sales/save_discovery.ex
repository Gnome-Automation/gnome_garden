defmodule GnomeGarden.Agents.Tools.SaveDiscovery do
  @moduledoc """
  Save discovered scraping configuration for a lead source.

  This tool is used by SmartScanner after it figures out how to scrape a site.
  The saved config allows future scans to be deterministic (no LLM needed).
  """

  use Jido.Action,
    name: "save_discovery",
    description: """
    Save discovered scraping configuration for a procurement site.
    Call this after you've figured out how to extract bids from a site.
    The saved config will be used for future deterministic (fast, cheap) scans.
    """,
    schema: [
      lead_source_id: [type: :string, required: true, doc: "ID of the LeadSource to update"],
      listing_url: [
        type: :string,
        required: true,
        doc: "URL of the bid listings page (after navigation)"
      ],
      listing_selector: [
        type: :string,
        required: true,
        doc: "CSS selector for bid rows (e.g., 'table.bids tr', '.bid-item')"
      ],
      title_selector: [type: :string, required: true, doc: "CSS selector for title within row"],
      date_selector: [type: :string, doc: "CSS selector for due date within row"],
      link_selector: [type: :string, doc: "CSS selector for detail link within row"],
      description_selector: [
        type: :string,
        doc: "CSS selector for description if visible in listing"
      ],
      agency_selector: [type: :string, doc: "CSS selector for agency/department"],
      pagination_type: [
        type: :string,
        doc: "Pagination type: 'numbered', 'load_more', 'infinite', 'none'"
      ],
      pagination_selector: [
        type: :string,
        doc: "CSS selector for pagination (next button or page links)"
      ],
      search_selector: [type: :string, doc: "CSS selector for search input if site has search"],
      notes: [type: :string, doc: "Any notes about the site structure"]
    ]

  @impl true
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

    case Ash.get(GnomeGarden.Agents.LeadSource, params.lead_source_id) do
      {:ok, source} ->
        case Ash.update(source, %{scrape_config: scrape_config}, action: :save_discovery) do
          {:ok, updated} ->
            {:ok,
             %{
               saved: true,
               lead_source_id: updated.id,
               name: updated.name,
               discovery_status: :discovered,
               message:
                 "Scraping config saved! Future scans will use deterministic scraping (no LLM)."
             }}

          {:error, error} ->
            {:error, "Failed to save discovery: #{inspect(error)}"}
        end

      {:error, _} ->
        {:error, "Lead source not found: #{params.lead_source_id}"}
    end
  end
end
