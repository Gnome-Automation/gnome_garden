defmodule GnomeGarden.Acquisition.ContactEnrichmentTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.ContactEnrichment
  alias GnomeGarden.Operations
  alias GnomeGarden.Search.Exa

  defp uniq, do: System.unique_integer([:positive])

  defp stub_contents(opts \\ []) do
    people = Keyword.get(opts, :people, [%{"name" => "Jane Doe", "title" => "VP Operations", "role" => "buyer", "email" => "jane.doe@acme.com"}])
    text = Keyword.get(opts, :text, "Main line (714) 775-5000")

    summary =
      Jason.encode!(%{"people" => people, "firmographic" => %{"summary" => "Maker of sauces."}})

    Req.Test.stub(Exa, fn conn ->
      Req.Test.json(conn, %{
        "costDollars" => %{"total" => 0.006},
        "results" => [
          %{
            "url" => "https://acme.example.com",
            "title" => "Acme",
            "text" => text,
            "summary" => summary,
            "subpages" => []
          }
        ]
      })
    end)
  end

  defp new_org do
    {:ok, org} =
      Operations.create_organization(%{name: "Acme #{uniq()}", website: "https://acme.example.com"})

    org
  end

  test "enrich persists a named person (inactive) with provenance + an affiliation, and enriches the org" do
    stub_contents()
    org = new_org()

    assert {:ok, result} =
             ContactEnrichment.enrich(%{organization_id: org.id, url: org.website, company: org.name})

    assert result.cost == 0.006
    assert [{:created, person_id}] = result.persisted.people

    {:ok, person} = Operations.get_person(person_id)
    assert person.first_name == "Jane"
    assert person.last_name == "Doe"
    assert to_string(person.email) == "jane.doe@acme.com"
    # Discovered, not yet human-verified.
    assert person.status == :inactive
    assert person.notes =~ "Discovered via contact enrichment"
    assert person.notes =~ "confidence:"

    {:ok, [affiliation]} = Operations.list_affiliations_for_organization(org.id)
    assert affiliation.person_id == person_id
    assert affiliation.title == "VP Operations"
    assert affiliation.contact_roles == ["buyer"]

    # Org got the firmographic note and a main line it didn't have before.
    {:ok, reloaded} = Operations.get_organization(org.id)
    assert reloaded.notes =~ "[enrichment] Maker of sauces."
    assert reloaded.phone =~ "775-5000"
  end

  test "preview writes nothing" do
    stub_contents()
    org = new_org()

    assert {:ok, result} =
             ContactEnrichment.preview(%{organization_id: org.id, url: org.website, company: org.name})

    assert result.persisted == nil
    # The named person was extracted but not persisted.
    assert [%{first_name: "Jane", last_name: "Doe"}] = result.people
    assert {:ok, []} = Operations.list_affiliations_for_organization(org.id)
  end

  test "dedups an existing person by email instead of creating a duplicate" do
    stub_contents()
    org = new_org()

    {:ok, _existing} =
      Operations.create_person(%{first_name: "Jane", last_name: "Doe", email: "jane.doe@acme.com"})

    assert {:ok, result} =
             ContactEnrichment.enrich(%{organization_id: org.id, url: org.website, company: org.name})

    assert [{:existing, _id}] = result.persisted.people

    {:ok, people} = Operations.list_people_for_organization(org.id)
    assert length(people) == 1
  end

  test "surfaces an Exa fetch error without persisting" do
    Req.Test.stub(Exa, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    org = new_org()

    assert {:error, {:http_error, 500, _}} =
             ContactEnrichment.enrich(%{organization_id: org.id, url: org.website, company: org.name})

    assert {:ok, []} = Operations.list_affiliations_for_organization(org.id)
  end
end
