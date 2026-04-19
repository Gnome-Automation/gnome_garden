defmodule GnomeGarden.Commercial.TargetAccountTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "promote_target_account_to_signal creates and links a signal" do
    {:ok, target_account} =
      Commercial.create_target_account(%{
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
      Commercial.create_target_observation(%{
        target_account_id: target_account.id,
        observation_type: :hiring,
        source_channel: :job_board,
        external_ref: "target-account-test:mesa-controls-brewing:hiring",
        source_url: "https://example.com/jobs/mesa-controls-brewing",
        observed_at: DateTime.utc_now(),
        confidence_score: 88,
        summary: "Hiring controls engineer for canning line expansion"
      })

    {:ok, promoted_target_account} =
      Commercial.promote_target_account_to_signal(target_account)

    assert promoted_target_account.status == :promoted
    assert promoted_target_account.promoted_signal_id

    {:ok, signal} = Commercial.get_signal(promoted_target_account.promoted_signal_id)

    assert signal.signal_type == :outbound_target
    assert signal.source_channel == :agent_discovery
    assert metadata_value(signal.metadata, :target_account_id) == target_account.id
  end

  test "merge_organization archives the duplicate and reassigns target accounts and affiliations" do
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

    {:ok, target_account} =
      Commercial.create_target_account(%{
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

    assert {:ok, refreshed_target_account} = Commercial.get_target_account(target_account.id)
    assert refreshed_target_account.organization_id == canonical_organization.id

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

    {:ok, target_account} =
      Commercial.create_target_account(%{
        name: "North Coast Packaging",
        website: "https://northcoastpackaging.com",
        contact_person_id: duplicate_person.id
      })

    assert {:ok, merged_source} =
             Operations.merge_person(duplicate_person, %{into_person_id: canonical_person.id})

    assert merged_source.status == :archived
    assert merged_source.merged_into_id == canonical_person.id

    assert {:ok, refreshed_target_account} = Commercial.get_target_account(target_account.id)
    assert refreshed_target_account.contact_person_id == canonical_person.id

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
