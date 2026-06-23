defmodule GnomeGarden.Procurement.ProcurementSourceImportTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Imports
  alias GnomeGarden.Procurement

  test "imports procurement source CSV rows idempotently" do
    rows = Imports.Csv.read!("priv/imports/procurement_sources_import_2026-06-12.csv")

    assert length(rows) == 87

    assert {:ok, first_result} =
             Procurement.import_procurement_source_seed_rows(rows, authorize?: false)

    assert first_result["imported_count"] == 87
    assert first_result["created_count"] == 84
    assert first_result["updated_count"] == 3
    assert first_result["configured_count"] == 9
    assert first_result["manual_count"] == 49
    assert first_result["source_ids"] |> Enum.uniq() |> length() == 84

    assert {:ok, sam_gov} = Procurement.get_procurement_source_by_url("https://sam.gov")
    assert sam_gov.source_type == :sam_gov
    assert sam_gov.region == :national
    assert sam_gov.priority == :low
    assert sam_gov.status == :approved
    assert sam_gov.config_status == :configured
    assert sam_gov.added_by == :import
    assert sam_gov.metadata["seed_import"]["source_category"] == "Gov"
    assert sam_gov.metadata["seed_import"]["import_batch"] == "lead_sources_2026_06_12"

    assert {:ok, cal_eprocure} =
             Procurement.get_procurement_source_by_url("https://caleprocure.ca.gov")

    assert cal_eprocure.requires_login == true

    assert cal_eprocure.notes =~
             "https://caleprocure.ca.gov/pages/BidderRegistration-BS3/bidder-registration-complete.aspx"

    assert {:ok, gsa_ebuy} = Procurement.get_procurement_source_by_url("https://www.ebuy.gsa.gov")
    assert gsa_ebuy.requires_login == true
    assert gsa_ebuy.config_status == :manual

    assert {:ok, second_result} =
             Procurement.import_procurement_source_seed_rows(rows, authorize?: false)

    assert second_result["imported_count"] == 87
    assert second_result["created_count"] == 0
    assert second_result["updated_count"] == 87
    assert second_result["configured_count"] == 0
    assert second_result["manual_count"] == 0
    assert second_result["source_ids"] |> Enum.uniq() |> length() == 84
  end
end
