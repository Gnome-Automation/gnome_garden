defmodule GnomeGarden.Agents.Procurement.ListingScannerTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Agents.Procurement.ListingScanner
  alias GnomeGarden.Procurement

  @source_url "https://vendors.planetbids.com/portal/23456/bo/bo-search"

  setup do
    original_username = System.get_env("PLANETBIDS_USERNAME")
    original_password = System.get_env("PLANETBIDS_PASSWORD")

    System.delete_env("PLANETBIDS_USERNAME")
    System.delete_env("PLANETBIDS_PASSWORD")

    on_exit(fn ->
      restore_env("PLANETBIDS_USERNAME", original_username)
      restore_env("PLANETBIDS_PASSWORD", original_password)
    end)

    :ok
  end

  test "public PlanetBids sources scan through HTTP without credentials" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Public PlanetBids Scanner Source",
        url: @source_url,
        source_type: :planetbids,
        portal_id: "23456",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: false
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: @source_url,
          listing_selector: "table tbody tr",
          title_selector: "td:nth-child(2)"
        }
      })

    http_get = fn @source_url, _opts ->
      {:ok, %{status: 200, body: listing_html()}}
    end

    assert {:ok, result} = ListingScanner.scan(source.id, %{http_get: http_get})

    assert result.extracted == 1
    assert result.source == source.name
  end

  test "login-gated PlanetBids sources still require credentials" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Private PlanetBids Scanner Source",
        url: @source_url <> "?private=1",
        source_type: :planetbids,
        portal_id: "23457",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, source} =
      Procurement.configure_procurement_source(source, %{
        scrape_config: %{
          listing_url: source.url,
          listing_selector: "table tbody tr",
          title_selector: "td:nth-child(2)"
        }
      })

    assert {:error, reason} = ListingScanner.scan(source.id)
    assert reason =~ "PlanetBids credentials are missing"
  end

  defp listing_html do
    """
    <table>
      <tbody>
        <tr class="bid-row" rowattribute="BID-23456">
          <td class="title">
            <a href="/portal/23456/bo/bo-detail/BID-23456">SCADA Controls Upgrade</a>
          </td>
          <td class="department">Regional Utility</td>
          <td class="due-date">12/30/2026</td>
          <td>
            <a href="/portal/23456/documents/rfp.pdf">RFP packet PDF</a>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
