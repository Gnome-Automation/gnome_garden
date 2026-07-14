defmodule GnomeGarden.Company.GrowthInitiativeTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Accounts
  alias GnomeGarden.Company
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "initiative lifecycle with actor stamps, evidence, and delivery links" do
    {actor_user, actor_member} = operator_fixture("Growth Owner")
    profile = profile_fixture()
    bid = bid_fixture()

    {:ok, initiative} =
      Company.create_growth_initiative(
        %{
          company_profile_id: profile.id,
          title: "DGS SB certification",
          category: :certification,
          expected_benefit: "5% state bid preference"
        },
        actor: actor_user
      )

    assert initiative.status == :idea
    assert initiative.created_by_team_member_id == actor_member.id

    {:ok, _evidence} =
      Company.create_growth_initiative_evidence(
        %{
          growth_initiative_id: initiative.id,
          bid_id: bid.id,
          gap_category: :missing_certification,
          quoted_requirement: "SB certification required at time of bid",
          confidence: :high
        },
        actor: actor_user
      )

    {:ok, [evidence]} = Company.list_growth_initiative_evidence(initiative.id)
    assert evidence.bid.title == bid.title
    assert evidence.created_by_team_member_id == actor_member.id

    {:ok, initiative} = Company.evaluate_growth_initiative(initiative, actor: actor_user)
    {:ok, initiative} = Company.plan_growth_initiative(initiative, %{}, actor: actor_user)
    {:ok, initiative} = Company.start_growth_initiative(initiative, actor: actor_user)
    assert initiative.status == :in_progress

    # Delivery hangs off the initiative through tasks and playbook runs.
    {:ok, _results} = Operations.ensure_starter_playbooks(authorize?: false)
    {:ok, playbook} = Operations.get_playbook_by_name("Customer onboarding", authorize?: false)

    {:ok, run} =
      Operations.apply_playbook(
        %{playbook_id: playbook.id, company_growth_initiative_id: initiative.id},
        actor: actor_user
      )

    assert run.company_growth_initiative_id == initiative.id

    {:ok, task} =
      Operations.create_task(
        %{title: "Submit application", company_growth_initiative_id: initiative.id},
        actor: actor_user
      )

    {:ok, linked_tasks} = Operations.list_tasks_by_growth_initiative(initiative.id)
    assert Enum.any?(linked_tasks, &(&1.id == task.id))
    assert length(linked_tasks) > 3

    {:ok, achieved} =
      Company.achieve_growth_initiative(
        initiative,
        %{outcome_notes: "Certified 2026-08"},
        actor: actor_user
      )

    assert achieved.status == :achieved
    assert achieved.achieved_at
    assert achieved.decided_by_team_member_id == actor_member.id

    assert {:error, error} =
             Company.update_growth_initiative(achieved, %{title: "rewrite history"})

    assert Exception.message(error) =~ "history"
    assert {:error, _error} = Company.delete_growth_initiative_idea(achieved)
  end

  test "declined initiatives keep their record and can be reconsidered" do
    profile = profile_fixture()

    {:ok, initiative} =
      Company.create_growth_initiative(%{
        company_profile_id: profile.id,
        title: "UL 508A panel shop",
        category: :certification
      })

    {:ok, declined} =
      Company.decline_growth_initiative(initiative, %{
        decision_notes: "We do not manufacture panels"
      })

    assert declined.status == :declined
    assert declined.declined_at
    assert {:error, _protected} = Company.delete_growth_initiative_idea(declined)

    {:ok, reconsidered} = Company.reconsider_growth_initiative(declined)
    assert reconsidered.status == :evaluating
    assert is_nil(reconsidered.declined_at)
  end

  test "qualification registry validates kind-specific details and tracks expiry" do
    profile = profile_fixture()

    assert {:error, error} =
             Company.create_company_qualification(%{
               company_profile_id: profile.id,
               kind: :bonding,
               name: "Surety program",
               issuing_authority: "Acme Surety",
               details: %{"surety" => "Acme"}
             })

    assert Exception.message(error) =~ "single_project_limit"

    assert {:error, error} =
             Company.create_company_qualification(%{
               company_profile_id: profile.id,
               kind: :license,
               name: "CSLB C-7",
               issuing_authority: "CSLB",
               details: %{"favorite_color" => "green"}
             })

    assert Exception.message(error) =~ "unknown keys"

    {:ok, qualification} =
      Company.create_company_qualification(%{
        company_profile_id: profile.id,
        kind: :license,
        name: "CSLB C-7",
        issuing_authority: "CSLB",
        identifier: "123456",
        expires_on: Date.add(Date.utc_today(), 40),
        renewal_lead_days: 60,
        details: %{"classification" => "C-7"}
      })

    assert qualification.status == :pending

    {:ok, active} = Company.activate_company_qualification(qualification, %{})
    assert active.status == :active

    {:ok, expiring} = Company.list_company_qualifications_expiring_within(60)
    assert Enum.any?(expiring, &(&1.id == qualification.id))

    {:ok, not_yet} = Company.list_company_qualifications_expiring_within(10)
    refute Enum.any?(not_yet, &(&1.id == qualification.id))

    {:ok, renewal_task} =
      Operations.create_task(%{
        title: "Renew C-7",
        company_qualification_id: qualification.id
      })

    {:ok, [linked]} = Operations.list_tasks_by_company_qualification(qualification.id)
    assert linked.id == renewal_task.id
  end

  defp operator_fixture(name) do
    password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

    {:ok, user} =
      Accounts.create_user_with_password(%{
        email: "growth-#{System.unique_integer([:positive, :monotonic])}@example.com",
        password: password,
        password_confirmation: password
      })

    {:ok, member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: name,
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
          Company.create_company_profile(%{
            key: "primary",
            name: "Gnome Automation"
          })

        profile
    end
  end

  defp bid_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Evidence bid",
        url: "https://example.com/bids/evidence-#{System.unique_integer([:positive])}",
        external_id: "EV-#{System.unique_integer([:positive])}",
        agency: "City of Anaheim",
        region: :oc,
        posted_at: ~U[2026-07-01 16:00:00Z],
        due_at: ~U[2026-08-01 23:59:00Z]
      })

    bid
  end
end
