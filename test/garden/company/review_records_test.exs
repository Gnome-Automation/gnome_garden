defmodule GnomeGarden.Company.ReviewRecordsTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultReviewRecords

  test "default compliance and source review records are idempotent" do
    first = DefaultReviewRecords.ensure_defaults()
    second = DefaultReviewRecords.ensure_defaults()

    assert first.profile.id == second.profile.id
    assert length(first.compliance_obligations) >= 5
    assert length(first.source_review_items) >= 5

    assert Enum.map(first.compliance_obligations, & &1.id) ==
             Enum.map(second.compliance_obligations, & &1.id)

    assert Enum.any?(first.compliance_obligations, &(&1.key == "registered-agent-renewal"))
    assert Enum.any?(first.source_review_items, &(&1.key == "relayfi-banking-conflict"))
  end

  test "compliance and source review workflow actions update status" do
    %{compliance_obligations: obligations, source_review_items: items} =
      DefaultReviewRecords.ensure_defaults()

    obligation = Enum.find(obligations, &(&1.key == "california-franchise-tax"))

    assert {:ok, completed} =
             Company.complete_company_compliance_obligation(obligation, %{
               completed_on: ~D[2026-06-14]
             })

    assert completed.status == :complete
    assert completed.completed_on == ~D[2026-06-14]

    source_item = Enum.find(items, &(&1.key == "company-profile-boilerplate"))

    assert {:ok, ignored} = Company.ignore_company_source_review_item(source_item)
    assert ignored.status == :ignored
  end
end
