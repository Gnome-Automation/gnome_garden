defmodule GnomeGarden.Automation.AutomationEngineTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Automation
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  describe "rule lifecycle" do
    test "drafts edit, published rules freeze, clones reopen" do
      {:ok, rule} =
        Automation.create_automation_rule(%{
          name: "High-score bid review",
          trigger_resource: "bid",
          trigger_action: "scored",
          criteria: [%{"field" => "score_tier", "op" => "eq", "value" => "hot"}],
          actions: [%{"type" => "create_task", "title" => "Review this bid"}]
        })

      assert rule.status == :draft

      {:ok, rule} = Automation.update_automation_rule(rule, %{description: "tuned"})
      {:ok, published} = Automation.publish_automation_rule(rule)
      assert published.status == :published
      assert published.published_at

      assert {:error, error} =
               Automation.update_automation_rule(published, %{description: "sneaky edit"})

      assert Exception.message(error) =~ "immutable"

      assert {:ok, clone} = Automation.clone_automation_rule(%{rule_id: published.id})
      assert clone.status == :draft
      assert clone.name == "High-score bid review (copy)"
      assert clone.actions == published.actions

      {:ok, disabled} = Automation.disable_automation_rule(published)
      assert disabled.status == :disabled
      {:ok, reenabled} = Automation.enable_automation_rule(disabled)
      assert reenabled.status == :published
    end

    test "malformed criteria and actions are rejected at write time" do
      assert {:error, error} =
               Automation.create_automation_rule(%{
                 name: "Bad criteria",
                 trigger_resource: "bid",
                 trigger_action: "scored",
                 criteria: [%{"field" => "x", "op" => "resembles", "value" => 1}]
               })

      assert Exception.message(error) =~ "op in"

      {:ok, empty_draft} =
        Automation.create_automation_rule(%{
          name: "Draft without actions",
          trigger_resource: "bid",
          trigger_action: "scored"
        })

      assert {:error, error} = Automation.publish_automation_rule(empty_draft)
      assert Exception.message(error) =~ "non-empty list of typed actions"

      assert {:error, error} =
               Automation.create_automation_rule(%{
                 name: "Arbitrary code",
                 trigger_resource: "bid",
                 trigger_action: "scored",
                 actions: [%{"type" => "eval", "code" => "System.cmd"}]
               })

      assert Exception.message(error) =~ "typed actions"
    end
  end

  describe "event capture and evaluation" do
    test "scoring a bid emits an event; processing fires matching rules idempotently" do
      {:ok, rule} = published_bid_rule()
      bid = bid_fixture()

      {:ok, _scored} =
        Procurement.score_bid(bid, %{score_service_match: 40, score_geography: 40})

      assert {:ok, [event]} = Automation.list_unprocessed_automation_events()
      assert event.resource == "bid"
      assert event.action == "scored"
      assert event.record_id == bid.id
      assert event.data["score_tier"] == "hot"

      {:ok, processed} = Automation.process_automation_event(event)
      assert processed.processed_at
      refute processed.error

      assert {:ok, [run]} = Automation.list_automation_runs_for_rule(rule.id)
      assert run.status == :succeeded
      assert [%{"type" => "create_task", "status" => "succeeded"} | _rest] = run.action_results
      assert run.rule_snapshot["name"] == rule.name

      assert {:ok, [task]} = Operations.list_tasks_by_bid(bid.id)
      assert task.title == "Review this bid"
      assert task.origin_resource == "automation_rule"
      assert task.origin_label == rule.name
      assert task.metadata["automation_depth"] == 1

      # Re-processing must not double-fire.
      {:ok, _again} = Automation.process_automation_event(processed)
      assert {:ok, [_only_run]} = Automation.list_automation_runs_for_rule(rule.id)
      assert {:ok, [_only_task]} = Operations.list_tasks_by_bid(bid.id)
    end

    test "criteria mismatches and unchanged scores fire nothing" do
      {:ok, rule} = published_bid_rule()
      bid = bid_fixture()

      {:ok, scored} = Procurement.score_bid(bid, %{score_service_match: 10})
      assert {:ok, [event]} = Automation.list_unprocessed_automation_events()
      {:ok, _processed} = Automation.process_automation_event(event)
      assert {:ok, []} = Automation.list_automation_runs_for_rule(rule.id)

      # Re-scoring with the same recommendation emits no new event.
      {:ok, _rescored} = Procurement.score_bid(scored, %{score_service_match: 12})
      assert {:ok, []} = Automation.list_unprocessed_automation_events()
    end

    test "apply_playbook actions run and recursion depth caps evaluation" do
      {:ok, _results} = Operations.ensure_starter_playbooks(authorize?: false)

      {:ok, rule} =
        Automation.create_automation_rule(%{
          name: "Pursue playbook on strong bids",
          trigger_resource: "bid",
          trigger_action: "scored",
          criteria: [%{"field" => "score_tier", "op" => "eq", "value" => "hot"}],
          actions: [%{"type" => "apply_playbook", "playbook_name" => "New bid review"}]
        })

      {:ok, _published} = Automation.publish_automation_rule(rule)

      bid = bid_fixture()
      {:ok, _scored} = Procurement.score_bid(bid, %{score_service_match: 40, score_geography: 40})

      assert {:ok, [event]} = Automation.list_unprocessed_automation_events()
      {:ok, _processed} = Automation.process_automation_event(event)

      assert {:ok, [playbook_run]} = Operations.list_playbook_runs_for_bid(bid.id)
      assert playbook_run.playbook_name == "New bid review"

      {:ok, deep_event} =
        Automation.record_automation_event(%{
          resource: "bid",
          action: "scored",
          record_id: bid.id,
          data: %{"score_tier" => "hot"},
          depth: 3
        })

      {:ok, capped} = Automation.process_automation_event(deep_event)
      assert capped.processed_at
      assert capped.error =~ "recursion depth"
      assert {:ok, [_still_one_run]} = Operations.list_playbook_runs_for_bid(bid.id)
    end

    test "failed actions land on the run and the event error summary" do
      {:ok, rule} =
        Automation.create_automation_rule(%{
          name: "Broken playbook reference",
          trigger_resource: "bid",
          trigger_action: "scored",
          actions: [%{"type" => "apply_playbook", "playbook_name" => "Does Not Exist"}]
        })

      {:ok, _published} = Automation.publish_automation_rule(rule)

      bid = bid_fixture()
      {:ok, _scored} = Procurement.score_bid(bid, %{score_service_match: 40, score_geography: 40})

      assert {:ok, [event]} = Automation.list_unprocessed_automation_events()
      {:ok, processed} = Automation.process_automation_event(event)

      assert processed.error =~ "Broken playbook reference"
      assert {:ok, [run]} = Automation.list_automation_runs_for_rule(rule.id)
      assert run.status == :failed
      assert [%{"status" => "failed"}] = run.action_results
    end
  end

  defp published_bid_rule do
    {:ok, rule} =
      Automation.create_automation_rule(%{
        name: "High-score bid review #{System.unique_integer([:positive])}",
        trigger_resource: "bid",
        trigger_action: "scored",
        criteria: [%{"field" => "score_tier", "op" => "eq", "value" => "hot"}],
        actions: [
          %{
            "type" => "create_task",
            "title" => "Review this bid",
            "task_type" => "review",
            "priority" => "high",
            "due_offset_days" => 2
          }
        ]
      })

    Automation.publish_automation_rule(rule)
  end

  defp bid_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Automation test bid",
        url: "https://example.com/bids/auto-#{System.unique_integer([:positive])}",
        external_id: "AUTO-#{System.unique_integer([:positive])}",
        agency: "City of Anaheim",
        region: :oc,
        posted_at: ~U[2026-07-01 16:00:00Z],
        due_at: ~U[2026-08-01 23:59:00Z]
      })

    bid
  end
end
