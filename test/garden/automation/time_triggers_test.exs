defmodule GnomeGarden.Automation.TimeTriggersTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Automation
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  test "time sweep emits deduped overdue-task and bid-deadline events" do
    {:ok, _task} =
      Operations.create_task(%{
        title: "Long overdue follow-up",
        due_at: DateTime.add(DateTime.utc_now(), -2, :day)
      })

    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Deadline bid",
        url: "https://example.com/bids/deadline-#{System.unique_integer([:positive])}",
        external_id: "DL-#{System.unique_integer([:positive])}",
        agency: "City of Anaheim",
        region: :oc,
        posted_at: DateTime.add(DateTime.utc_now(), -10, :day),
        due_at: DateTime.add(DateTime.utc_now(), 5, :day)
      })

    assert {:ok, first} = Automation.sweep_automation_time_triggers(authorize?: false)
    assert first["task_overdue"] == 1
    assert first["bid_due_soon"] == 1

    {:ok, events} = Automation.list_unprocessed_automation_events()
    assert Enum.any?(events, &(&1.resource == "task" and &1.action == "overdue"))

    bid_event = Enum.find(events, &(&1.resource == "bid" and &1.action == "due_soon"))
    assert bid_event.record_id == bid.id
    assert bid_event.data["days_until_due"] in [4, 5]

    # Second sweep observes the same subjects but emits nothing new.
    assert {:ok, second} = Automation.sweep_automation_time_triggers(authorize?: false)
    assert second["task_overdue"] == 0
    assert second["bid_due_soon"] == 0
  end

  test "deadline starter rule fires from a due_soon event once published" do
    {:ok, results} = Automation.ensure_starter_automation_rules(authorize?: false)
    assert results["Bid deadline approaching"] == :created

    # Idempotent: second install changes nothing.
    {:ok, again} = Automation.ensure_starter_automation_rules(authorize?: false)
    assert again["Bid deadline approaching"] == :existing

    {:ok, rule} =
      Automation.get_automation_rule_by_name("Bid deadline approaching", authorize?: false)

    # Starters install as drafts and do not fire until published.
    assert rule.status == :draft
    {:ok, _published} = Automation.publish_automation_rule(rule)

    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Closing soon bid",
        url: "https://example.com/bids/closing-#{System.unique_integer([:positive])}",
        external_id: "CS-#{System.unique_integer([:positive])}",
        agency: "City of Anaheim",
        region: :oc,
        posted_at: DateTime.add(DateTime.utc_now(), -10, :day),
        due_at: DateTime.add(DateTime.utc_now(), 3, :day)
      })

    {:ok, event} =
      Automation.record_automation_event(%{
        resource: "bid",
        action: "due_soon",
        record_id: bid.id,
        data: %{"days_until_due" => 3},
        dedupe_key: "bid_due_soon:#{bid.id}"
      })

    {:ok, processed} = Automation.process_automation_event(event)
    refute processed.error

    assert {:ok, [task]} = Operations.list_tasks_by_bid(bid.id)
    assert task.title == "Submission deadline approaching"
    assert task.priority == :urgent
  end

  test "rule dry run reports would-fire counts without executing" do
    {:ok, rule} =
      Automation.create_automation_rule(%{
        name: "Dry run subject",
        trigger_resource: "bid",
        trigger_action: "due_soon",
        criteria: [%{"field" => "days_until_due", "op" => "lte", "value" => 7}],
        actions: [%{"type" => "create_task", "title" => "Check the deadline"}]
      })

    {:ok, _near} =
      Automation.record_automation_event(%{
        resource: "bid",
        action: "due_soon",
        record_id: Ecto.UUID.generate(),
        data: %{"days_until_due" => 3}
      })

    {:ok, _far} =
      Automation.record_automation_event(%{
        resource: "bid",
        action: "due_soon",
        record_id: Ecto.UUID.generate(),
        data: %{"days_until_due" => 12}
      })

    {:ok, result} = Automation.dry_run_automation_rule(rule.id, authorize?: false)

    assert result["tested_events"] == 2
    assert result["would_fire"] == 1
    assert {:ok, []} = Automation.list_automation_runs_for_rule(rule.id)
    assert {:ok, []} = Operations.list_tasks(authorize?: false)
  end
end
