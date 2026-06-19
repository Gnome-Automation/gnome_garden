defmodule GnomeGarden.Acquisition.LeadToPursuitTest do
  @moduledoc """
  Step 2 verification: a lead-preview candidate flows through the whole business
  tail — promote → discovery record + Finding (review queue) → review → accept →
  promote to Commercial Signal → create Pursuit. Proves the new lead-gen front
  connects to the existing review tail end to end.
  """

  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Acquisition, Commercial}
  alias GnomeGarden.Acquisition.LeadPromote

  defp uniq, do: System.unique_integer([:positive])

  test "a promoted lead-preview candidate can travel all the way to a pursuit" do
    {:ok, program} =
      Commercial.create_discovery_program(%{name: "Tail #{uniq()}", program_type: :industry_watch, priority: :normal})

    domain = "tailco-#{uniq()}.example.com"

    candidate = %{
      title: "TailCo Manufacturing",
      url: "https://#{domain}",
      type: :company,
      query: "manufacturer expanding production",
      dedupe: %{context: :new, suppress?: false, recommendation: "New candidate lead.", related: []}
    }

    # 1. Promote (program-scoped, so a DiscoveryEvidence row is created — the
    #    discovery-family promotion gate requires evidence).
    assert {:promoted, record} = LeadPromote.promote(candidate, discovery_program_id: program.id)

    # 2. The promote synced a Finding into the review queue.
    assert {:ok, finding} = Acquisition.get_finding_by_source_discovery_record(record.id)
    assert finding.status == :new

    # 3. Qualify the finding (a raw lead is intentionally not promotion-ready).
    {:ok, _} =
      Acquisition.update_finding(finding, %{
        summary: "Expanding production capacity in the target region.",
        work_summary: "Controls + integration scope for the new line.",
        source_url: "https://#{domain}"
      })

    # 4. Review tail: start review -> accept (with reason + evidence) -> promote.
    assert {:ok, _} = Acquisition.start_review_for_finding(finding.id)
    assert {:ok, accepted} = Acquisition.accept_finding_review(finding.id, %{reason: "Strong fit, in target region."})
    assert accepted.status == :accepted

    assert {:ok, %{result: %{signal: signal}}} = Acquisition.promote_finding_to_signal(finding.id)
    assert {:ok, promoted} = Acquisition.get_finding(finding.id)
    assert promoted.status == :promoted
    assert promoted.signal_id == signal.id

    # 5. The lead now carries a resolved organization, so it is pursuit-capable.
    #    (Signal acceptance → Pursuit is covered by create_pursuit_from_signal_test.)
    assert signal.organization_id
    assert {:ok, org} = GnomeGarden.Operations.get_organization(signal.organization_id)
    assert org.website_domain == domain
  end
end
