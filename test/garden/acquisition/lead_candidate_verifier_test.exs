defmodule GnomeGarden.Acquisition.LeadCandidateVerifierTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Acquisition, Commercial, Operations}
  alias GnomeGarden.Acquisition.LeadCandidateVerifier
  alias GnomeGarden.Acquisition.ProgramSourcePolicy
  alias GnomeGarden.Search.Exa

  test "verifies, admits, and replays a qualified candidate without downstream writes" do
    program = program("Qualified")
    domain = unique_domain("qualified")
    preview_run = preview_run(program, [candidate(domain)])
    test_pid = self()

    stub_contents(fn conn ->
      send(test_pid, :contents_requested)
      contents_response(conn, domain)
    end)

    {:ok, organizations_before} = Operations.list_organizations()
    {:ok, records_before} = Commercial.list_discovery_records()

    assert {:ok, result} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert result.verified == 1
    assert result.admitted == 1
    assert result.unresolved == 0
    assert_received :contents_requested

    assert {:ok, [admission]} = Acquisition.list_finding_admissions_for_run(preview_run.id)
    assert admission.finding.status == :new
    assert admission.finding.finding_family == :discovery
    assert admission.finding.external_ref == "commercial-company-domain:#{domain}"

    assert admission.finding.metadata["lead_preview_candidate_id"] ==
             admission.lead_preview_candidate_id

    assert {:ok, replayed} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert replayed.admitted == 1
    assert replayed.reused_admissions == 1
    refute_received :contents_requested

    assert {:ok, [_admission]} = Acquisition.list_finding_admissions_for_run(preview_run.id)
    assert {:ok, findings} = Acquisition.list_findings()
    assert Enum.count(findings, &(&1.external_ref == "commercial-company-domain:#{domain}")) == 1

    assert {:ok, organizations_after} = Operations.list_organizations()
    assert {:ok, records_after} = Commercial.list_discovery_records()
    assert length(organizations_after) == length(organizations_before)
    assert length(records_after) == length(records_before)
  end

  test "records suppressed and duplicate candidates without paid enrichment" do
    program = program("Ineligible")
    suppressed_domain = unique_domain("suppressed")
    duplicate_domain = unique_domain("duplicate")

    preview_run =
      preview_run(program, [
        candidate(suppressed_domain, suppressed: true, route: :skip),
        candidate(duplicate_domain, dedupe_context: :duplicate_existing_lead, route: :skip)
      ])

    Req.Test.stub(Exa, fn _conn -> flunk("ineligible candidates must not call Exa Contents") end)

    assert {:ok, result} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert result.ineligible == 2
    assert result.enrichment_attempts == 0
    assert result.admitted == 0

    {:ok, candidates} = Acquisition.list_lead_preview_candidates_for_run(preview_run.id)

    reasons =
      Map.new(candidates, fn candidate ->
        {:ok, verification} = Acquisition.get_lead_candidate_verification(candidate.id)
        {candidate.website_domain, verification.reason}
      end)

    assert reasons[suppressed_domain] == :suppressed
    assert reasons[duplicate_domain] == :duplicate_context
  end

  test "verifies candidates when Exa omits its optional relevance score" do
    program = program("Optional Search Score")
    domain = unique_domain("optional-score")

    preview_run =
      preview_run(program, [
        candidate(domain, metadata: %{"related" => []})
      ])

    stub_contents(fn conn -> contents_response(conn, domain) end)

    assert {:ok, result} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert result.verified == 1
    assert result.admitted == 1
    assert result.ineligible == 0

    assert {:ok, [candidate]} = Acquisition.list_lead_preview_candidates_for_run(preview_run.id)
    assert {:ok, verification} = Acquisition.get_lead_candidate_verification(candidate.id)
    assert is_nil(verification.search_score)
    assert verification.verification_score == 50
  end

  test "still rejects candidates below the configured search-score floor" do
    program = program("Low Search Score")
    domain = unique_domain("low-score")

    preview_run =
      preview_run(program, [
        candidate(domain, metadata: %{"related" => [], "exa_score" => 0.05})
      ])

    Req.Test.stub(Exa, fn _conn -> flunk("below-score candidates must not call Exa Contents") end)

    assert {:ok, result} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert result.verified == 0
    assert result.ineligible == 1

    assert {:ok, [candidate]} = Acquisition.list_lead_preview_candidates_for_run(preview_run.id)
    assert {:ok, verification} = Acquisition.get_lead_candidate_verification(candidate.id)
    assert verification.reason == :below_search_score
  end

  test "enrichment policy none skips Exa Contents and records an explicit reason" do
    program = program("No Enrichment")
    domain = unique_domain("no-enrichment")
    preview_run = preview_run(program, [candidate(domain)], %{enrichment_policy: :none})

    Req.Test.stub(Exa, fn _conn -> flunk("disabled enrichment must not call Exa Contents") end)

    assert {:ok, result} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert result.enrichment_attempts == 0
    assert result.admitted == 0
    assert result.unresolved == 1

    assert {:ok, [candidate]} =
             Acquisition.list_lead_preview_candidates_for_run(preview_run.id)

    assert {:ok, verification} = Acquisition.get_lead_candidate_verification(candidate.id)
    assert verification.reason == :enrichment_disabled
  end

  test "keeps insufficient and failed evidence unresolved or ineligible with provenance" do
    program = program("Evidence")
    thin_domain = unique_domain("thin")
    failed_domain = unique_domain("failed")
    preview_run = preview_run(program, [candidate(thin_domain), candidate(failed_domain)])

    Req.Test.stub(Exa, fn conn ->
      [url] = request_urls(conn)

      if String.contains?(url, thin_domain) do
        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.01},
          "results" => [
            %{
              "url" => url,
              "title" => "Thin evidence",
              "text" => "Too little evidence",
              "summary" =>
                Jason.encode!(%{
                  "company_name" => "Thin",
                  "business_description" => "Thin",
                  "is_operating_company" => true
                })
            }
          ]
        })
      else
        conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"error" => "rate limited"})
      end
    end)

    assert {:ok, result} = Acquisition.verify_lead_preview_run(preview_run.id)
    assert result.ineligible == 1
    assert result.unresolved == 1
    assert result.admitted == 0

    {:ok, candidates} = Acquisition.list_lead_preview_candidates_for_run(preview_run.id)

    reasons =
      Map.new(candidates, fn candidate ->
        {:ok, verification} = Acquisition.get_lead_candidate_verification(candidate.id)
        {candidate.website_domain, verification}
      end)

    assert reasons[thin_domain].reason == :insufficient_evidence
    assert reasons[thin_domain].evidence["citations"] != []
    assert reasons[failed_domain].reason == :provider_failure
    assert reasons[failed_domain].evidence["error"]
  end

  test "atomically enforces per-run and daily Finding capacity" do
    program = program("Capacity")
    first_domain = unique_domain("first")
    second_domain = unique_domain("second")

    preview_run =
      preview_run(program, [candidate(first_domain), candidate(second_domain)], %{
        finding_limit_per_run: 1,
        finding_limit_per_day: 1
      })

    stub_contents(fn conn ->
      [url] = request_urls(conn)
      contents_response(conn, URI.parse(url).host |> String.trim_leading("www."))
    end)

    assert {:ok, result} = LeadCandidateVerifier.verify_run(preview_run.id)

    assert result.verified == 2
    assert result.admitted == 1
    assert result.capacity_deferred == 1
    assert {:ok, [_admission]} = Acquisition.list_finding_admissions_for_run(preview_run.id)

    assert {:ok, run_capacity} =
             Acquisition.get_finding_admission_capacity(:run, preview_run.id)

    assert run_capacity.admitted_count == 1
    assert run_capacity.admission_limit == 1
  end

  defp program(label) do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "#{label} #{System.unique_integer([:positive])}",
        target_regions: ["orange county"],
        target_industries: ["manufacturing"],
        search_terms: ["#{label} manufacturer"]
      })

    program
  end

  defp preview_run(program, candidates, policy_attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    program_source = activate_exa_program_source!(program, policy_attrs)

    {:ok, run} =
      Acquisition.create_lead_preview_run(%{
        source: :exa,
        status: :completed,
        started_at: now,
        finished_at: now,
        query_count: 1,
        candidate_count: length(candidates),
        promotable_count: Enum.count(candidates, &(&1.route == :promote)),
        total_cost: Decimal.new("0.01"),
        discovery_program_id: program.id,
        metadata:
          program_source
          |> ProgramSourcePolicy.snapshot()
          |> Map.put("provider_budget_idempotency_key", Ecto.UUID.generate()),
        candidates: candidates
      })

    run
  end

  defp candidate(domain, overrides \\ []) do
    Map.merge(
      %{
        title: "#{domain} manufacturer",
        url: "https://#{domain}",
        website_domain: domain,
        query: "manufacturer orange county",
        candidate_type: :company,
        dedupe_context: :new,
        route: :promote,
        suppressed: false,
        recommendation: "New candidate lead.",
        rank: 0,
        status: :pending,
        metadata: %{"related" => [], "exa_score" => 0.9}
      },
      Map.new(overrides)
    )
  end

  defp stub_contents(fun), do: Req.Test.stub(Exa, fun)

  defp contents_response(conn, domain) do
    text = String.duplicate("#{domain} manufactures industrial equipment in Orange County. ", 20)

    Req.Test.json(conn, %{
      "costDollars" => %{"total" => 0.02},
      "results" => [
        %{
          "url" => "https://#{domain}",
          "title" => "#{domain} capabilities",
          "text" => text,
          "summary" =>
            Jason.encode!(%{
              "company_name" => domain,
              "business_description" => "Industrial equipment manufacturer",
              "is_operating_company" => true
            }),
          "subpages" => []
        }
      ]
    })
  end

  defp request_urls(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)["urls"]
  end

  defp unique_domain(prefix),
    do: "#{prefix}-#{System.unique_integer([:positive])}.example.com"
end
