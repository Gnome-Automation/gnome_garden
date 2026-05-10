defmodule GnomeGarden.Commercial.DiscoveryRecordTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "acquisition review promotes a discovery record and links a signal" do
    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        name: "Mesa Controls Brewing",
        website: "https://www.mesacontrolsbrewing.com",
        location: "Anaheim, CA",
        region: "oc",
        industry: "brewery",
        fit_score: 81,
        intent_score: 88,
        notes: "Hiring controls engineer after adding a second canning line."
      })

    {:ok, _observation} =
      Commercial.create_discovery_evidence(%{
        discovery_record_id: discovery_record.id,
        observation_type: :hiring,
        source_channel: :job_board,
        external_ref: "discovery-record-test:mesa-controls-brewing:hiring",
        source_url: "https://example.com/jobs/mesa-controls-brewing",
        observed_at: DateTime.utc_now(),
        confidence_score: 88,
        summary: "Hiring controls engineer for canning line expansion"
      })

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified discovery target with supporting evidence."
             })

    assert {:ok, %{finding: promoted_finding}} = Acquisition.promote_finding_to_signal(finding.id)

    {:ok, promoted_discovery_record} = Commercial.get_discovery_record(discovery_record.id)

    assert promoted_discovery_record.status == :promoted
    assert promoted_discovery_record.promoted_signal_id
    assert promoted_finding.signal_id == promoted_discovery_record.promoted_signal_id

    {:ok, signal} = Commercial.get_signal(promoted_discovery_record.promoted_signal_id)

    assert signal.signal_type == :outbound_target
    assert signal.source_channel == :agent_discovery
    assert metadata_value(signal.metadata, :discovery_record_id) == discovery_record.id
    assert metadata_value(signal.metadata, :finding_id) == finding.id
    assert metadata_value(signal.metadata, :source) == "discovery_record_promotion"
    assert signal.external_ref == "discovery_record:#{discovery_record.id}"
  end

  test "acquisition review requires discovery evidence before accepting" do
    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        name: "No Evidence Controls",
        website: "https://www.no-evidence-controls.example.com",
        location: "Anaheim, CA",
        region: "oc",
        industry: "food",
        fit_score: 81,
        intent_score: 88,
        notes: "Looks interesting, but has no structured evidence yet."
      })

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:error, error} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Looks interesting, but has no structured evidence yet."
             })

    assert inspect(error) =~ "Add at least one piece of discovery evidence before accepting."
  end

  test "creating discovery evidence refreshes the acquisition finding summary" do
    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        name: "Coastal Systems Foods",
        website: "https://coastalsystemsfoods.example.com",
        notes: "Initial discovery record without evidence"
      })

    {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(discovery_record.id)
    assert finding.summary == "Initial discovery record without evidence"

    {:ok, _observation} =
      Commercial.create_discovery_evidence(%{
        discovery_record_id: discovery_record.id,
        observation_type: :expansion,
        source_channel: :news_site,
        external_ref: "discovery-record-test:coastal-systems-foods:expansion",
        source_url: "https://example.com/coastal-systems-foods-expansion",
        observed_at: ~U[2026-04-20 12:00:00Z],
        confidence_score: 86,
        summary: "Expansion signal found on company site",
        evidence_points: ["new line", "modernization"]
      })

    {:ok, refreshed_finding} =
      Acquisition.get_finding_by_source_discovery_record(discovery_record.id)

    assert refreshed_finding.summary == "Expansion signal found on company site"
    assert refreshed_finding.observed_at == ~U[2026-04-20 12:00:00Z]
    assert refreshed_finding.finding_type == :expansion_signal
  end

  test "merge_organization archives the duplicate and reassigns discovery records and affiliations" do
    {:ok, canonical_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        status: :prospect,
        relationship_roles: ["prospect"],
        website: "https://northcoastpackaging.com"
      })

    {:ok, duplicate_organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging, Inc.",
        status: :active,
        relationship_roles: ["prospect", "customer"]
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        email: "maya@northcoastpackaging.com"
      })

    {:ok, _affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: duplicate_organization.id,
        person_id: person.id,
        title: "Controls Engineer",
        is_primary: true
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.com",
        organization_id: duplicate_organization.id
      })

    assert {:ok, merged_source} =
             Operations.merge_organization(
               duplicate_organization,
               %{into_organization_id: canonical_organization.id}
             )

    assert merged_source.status == :archived
    assert merged_source.merged_into_id == canonical_organization.id

    assert {:ok, refreshed_discovery_record} =
             Commercial.get_discovery_record(discovery_record.id)

    assert refreshed_discovery_record.organization_id == canonical_organization.id

    assert {:ok, [canonical_affiliation]} =
             Operations.list_affiliations_for_organization(canonical_organization.id)

    assert canonical_affiliation.person_id == person.id
    assert canonical_affiliation.status == :active

    assert {:ok, [former_affiliation]} =
             Operations.list_affiliations_for_organization(duplicate_organization.id)

    assert former_affiliation.person_id == person.id
    assert former_affiliation.status == :former
  end

  test "merge_person archives the duplicate and reassigns active people links" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "North Coast Packaging",
        status: :prospect,
        relationship_roles: ["prospect"],
        website: "https://northcoastpackaging.com"
      })

    {:ok, canonical_person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        email: "maya@northcoastpackaging.com"
      })

    {:ok, duplicate_person} =
      Operations.create_person(%{
        first_name: "Maya",
        last_name: "Lopez",
        phone: "555-0100"
      })

    {:ok, _affiliation} =
      Operations.create_organization_affiliation(%{
        organization_id: organization.id,
        person_id: duplicate_person.id,
        title: "Controls Engineer",
        is_primary: true
      })

    {:ok, discovery_record} =
      Commercial.create_discovery_record(%{
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.com",
        contact_person_id: duplicate_person.id
      })

    assert {:ok, merged_source} =
             Operations.merge_person(duplicate_person, %{into_person_id: canonical_person.id})

    assert merged_source.status == :archived
    assert merged_source.merged_into_id == canonical_person.id

    assert {:ok, refreshed_discovery_record} =
             Commercial.get_discovery_record(discovery_record.id)

    assert refreshed_discovery_record.contact_person_id == canonical_person.id

    assert {:ok, [canonical_affiliation]} =
             Operations.list_affiliations_for_person(canonical_person.id)

    assert canonical_affiliation.organization_id == organization.id
    assert canonical_affiliation.status == :active

    assert {:ok, [former_affiliation]} =
             Operations.list_affiliations_for_person(duplicate_person.id)

    assert former_affiliation.organization_id == organization.id
    assert former_affiliation.status == :former
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
