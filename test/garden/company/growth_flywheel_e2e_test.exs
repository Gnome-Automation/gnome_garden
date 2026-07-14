defmodule GnomeGarden.Company.GrowthFlywheelE2ETest do
  @moduledoc """
  Epic gkc.9: the full loop in one path — repeated bid gaps → recommendation
  → operator approval → initiative with linked evidence → delivery →
  achieved qualification → requirement-aware eligibility → renewal episode
  filing the renewal task to the qualification owner.
  """

  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Accounts
  alias GnomeGarden.Automation
  alias GnomeGarden.Company
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "capability gap closes into eligibility and renewal automation" do
    {actor_user, actor_member} = operator_fixture()
    profile = profile_fixture()

    # 1. Two bids lost to the same structured gap inside the window.
    lost_bids =
      for n <- 1..2 do
        bid = bid_fixture("Bond-blocked bid #{n}")
        {:ok, bid} = Procurement.review_bid(bid)
        {:ok, bid} = Procurement.pursue_bid(bid)

        {:ok, bid} =
          Procurement.lose_bid(bid, %{
            notes: "Could not meet bond requirement",
            capability_gaps: [:bond_capacity]
          })

        bid
      end

    # Bids now surface the missing requirement as an eligibility gap.
    first_lost = Ash.load!(hd(lost_bids), [:eligibility_gaps], authorize?: false)
    assert :bond_capacity in first_lost.eligibility_gaps

    # 2. The scan proposes exactly one recommendation (dedupe on rescan).
    {:ok, [recommendation]} = Company.scan_growth_gaps(window_days: 90, repeat_threshold: 2)
    assert recommendation.target_domain == :company
    {:ok, []} = Company.scan_growth_gaps(window_days: 90, repeat_threshold: 2)

    # 3. Operator approval transactionally creates the initiative + evidence.
    {:ok, initiative} =
      Company.approve_growth_recommendation(recommendation, actor: actor_user)

    assert initiative.category == :bonding
    {:ok, evidence} = Company.list_growth_initiative_evidence(initiative.id)
    assert length(evidence) == 2

    {:ok, applied} = Operations.get_learning_recommendation(recommendation.id)
    assert applied.status == :applied

    # 4. Delivery: plan, start, execute, achieve.
    {:ok, initiative} = Company.plan_growth_initiative(initiative, %{}, actor: actor_user)
    {:ok, initiative} = Company.start_growth_initiative(initiative, actor: actor_user)

    {:ok, _task} =
      Operations.create_task(
        %{title: "Secure surety program", company_growth_initiative_id: initiative.id},
        actor: actor_user
      )

    {:ok, qualification} =
      Company.create_company_qualification(%{
        company_profile_id: profile.id,
        kind: :bonding,
        name: "Surety bond program",
        issuing_authority: "Acme Surety",
        identifier: "SB-777",
        expires_on: Date.add(Date.utc_today(), 10),
        renewal_lead_days: 30,
        owner_team_member_id: actor_member.id,
        growth_initiative_id: initiative.id,
        details: %{"single_project_limit" => "$1M", "aggregate_limit" => "$2M"}
      })

    {:ok, _active} = Company.activate_company_qualification(qualification, %{})

    {:ok, _achieved} =
      Company.achieve_growth_initiative(
        initiative,
        %{outcome_notes: "Bonded to $1M single / $2M aggregate"},
        actor: actor_user
      )

    # 5. Eligibility flips: the same bid no longer reports the gap.
    recheck = Ash.load!(hd(lost_bids), [:eligibility_gaps], authorize?: false)
    refute :bond_capacity in recheck.eligibility_gaps

    # 6. Renewal automation: the expiring qualification emits a deduped
    #    episode and the published starter rule files the renewal task to
    #    the qualification's owner.
    {:ok, _results} =
      Automation.ensure_starter_automation_rules(%{}, authorize?: false)

    {:ok, renewal_rule} =
      Automation.get_automation_rule_by_name("Qualification renewal due", authorize?: false)

    {:ok, _published} = Automation.publish_automation_rule(renewal_rule)

    assert {:ok, %{"qualification_expiring" => 1}} =
             Automation.sweep_automation_time_triggers(authorize?: false)

    # Second sweep: same episode, nothing new.
    assert {:ok, %{"qualification_expiring" => 0}} =
             Automation.sweep_automation_time_triggers(authorize?: false)

    {:ok, events} = Automation.list_unprocessed_automation_events()
    renewal_event = Enum.find(events, &(&1.resource == "company_qualification"))
    assert renewal_event.data["days_until_expiry"] == 10

    {:ok, processed} = Automation.process_automation_event(renewal_event)
    refute processed.error

    {:ok, [renewal_task]} = Operations.list_tasks_by_company_qualification(qualification.id)
    assert renewal_task.title == "Complete qualification renewal"
    assert renewal_task.owner_team_member_id == actor_member.id
    assert renewal_task.priority == :high
  end

  defp operator_fixture do
    password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

    {:ok, user} =
      Accounts.create_user_with_password(%{
        email: "flywheel-#{System.unique_integer([:positive, :monotonic])}@example.com",
        password: password,
        password_confirmation: password
      })

    {:ok, member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: "Flywheel Operator",
        role: :operator,
        status: :active
      })

    {user, member}
  end

  defp profile_fixture do
    case Company.get_primary_company_profile(authorize?: false) do
      {:ok, profile} ->
        profile

      {:error, _none} ->
        {:ok, profile} =
          Company.create_company_profile(%{key: "primary", name: "Gnome Automation"})

        profile
    end
  end

  defp bid_fixture(title) do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: title,
        url: "https://example.com/bids/fly-#{System.unique_integer([:positive])}",
        external_id: "FLY-#{System.unique_integer([:positive])}",
        agency: "City of Anaheim",
        region: :oc,
        posted_at: DateTime.add(DateTime.utc_now(), -20, :day),
        due_at: DateTime.add(DateTime.utc_now(), -5, :day)
      })

    bid
  end
end
