defmodule GnomeGarden.Acquisition.ContactEnrichmentTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition
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

  describe "enrich_finding (analyzer/RFP text path)" do
    # The named contact comes from the LLM seam (injected here for offline
    # testing); regex picks up the officer's email/phone directly.
    defp officer_llm do
      fn _text, _opts ->
        {:ok, %{people: [%{name: "Pat Buyer", title: "Senior Buyer", role: "procurement"}], firmographic: nil, cost: 0.0}}
      end
    end

    defp rfp_finding(attrs \\ %{}) do
      base = %{
        external_ref: "rfp-#{uniq()}",
        title: "Control System Integration Services RFP",
        finding_family: :procurement,
        finding_type: :bid_notice,
        status: :new,
        observed_at: DateTime.utc_now(),
        summary: "Questions to Pat Buyer, Senior Buyer, pbuyer@city.example.gov, (562) 555-0100.",
        work_summary: "SCADA/PLC controls integration scope."
      }

      {:ok, finding} = Acquisition.create_finding(Map.merge(base, attrs))
      finding
    end

    test "extracts the procurement officer and sets the finding's person_id" do
      finding = rfp_finding()

      assert {:ok, result} = ContactEnrichment.enrich_finding(finding.id, llm_fun: officer_llm())

      assert [{:created, person_id}] = result.persisted.people
      assert {:updated, ^person_id} = result.persisted.finding

      {:ok, person} = Operations.get_person(person_id)
      assert person.first_name == "Pat"
      assert person.last_name == "Buyer"
      assert person.status == :inactive
      # The regex-captured email was associated to the named officer (its local
      # part "pbuyer" matches the surname), not left as a loose org contact.
      assert to_string(person.email) == "pbuyer@city.example.gov"

      {:ok, reloaded} = Acquisition.get_finding(finding.id)
      assert reloaded.person_id == person_id
    end

    test "preview_finding writes nothing" do
      finding = rfp_finding()

      assert {:ok, result} = ContactEnrichment.preview_finding(finding.id, llm_fun: officer_llm())
      assert result.persisted == nil

      {:ok, reloaded} = Acquisition.get_finding(finding.id)
      assert reloaded.person_id == nil
    end

    test "returns an error when the finding has no analyzed text" do
      finding = rfp_finding(%{summary: nil, work_summary: nil})
      assert {:error, :no_analyzed_document_text} = ContactEnrichment.enrich_finding(finding.id)
    end

    test "extracts a generic contact from the server-rendered detail page and persists it" do
      url = "https://agency.example.gov/rfp/controls-25-001/"
      finding = rfp_finding(%{summary: nil, work_summary: nil, source_url: url})

      html =
        "<html><body><style>.x{}</style><main>Control System Integration RFP. " <>
          "For questions contact procurement@agency.example.gov or call (562) 555-0144. " <>
          "Proposals due 2026-08-01.</main></body></html>"

      http_get = fn ^url, _opts -> {:ok, %{status: 200, body: html}} end

      assert {:ok, result} = ContactEnrichment.enrich_finding(finding.id, http_get: http_get, use_llm: false)

      # Generic inbox email/phone pulled from the detail page (no named person).
      assert "procurement@agency.example.gov" in result.org_contact.emails
      assert {:saved, _} = result.persisted.contact_info

      {:ok, reloaded} = Acquisition.get_finding(finding.id)
      assert reloaded.metadata["enrichment"]["contact_emails"] == ["procurement@agency.example.gov"]
      assert Enum.any?(reloaded.metadata["enrichment"]["contact_phones"], &(&1 =~ "555-0144"))
    end
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
