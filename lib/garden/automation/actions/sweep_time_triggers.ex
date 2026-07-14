defmodule GnomeGarden.Automation.Actions.SweepTimeTriggers do
  @moduledoc """
  Emits time-based automation events into the same evaluator as record
  events.

  Deadline events are episodic: a bid emits once per threshold bucket
  (14/7/3/1 days) per due date, so a rule keyed on `deadline_bucket` fires
  exactly once at each escalation and a rescheduled deadline starts fresh
  episodes. Overdue-task events are keyed by task and due date, so a
  rescheduled task can go overdue again. Event depth is inherited from
  automation-created tasks so recursion cannot reset through time triggers.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Automation
  alias GnomeGarden.Company
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @deadline_buckets [14, 7, 3, 1]
  @bid_due_window_days List.first(@deadline_buckets)

  @impl true
  def run(_input, _opts, _context) do
    {:ok,
     %{
       "task_overdue" => sweep_overdue_tasks(),
       "bid_due_soon" => sweep_bids_due_soon(),
       "qualification_expiring" => sweep_expiring_qualifications()
     }}
  end

  defp sweep_overdue_tasks do
    {:ok, tasks} = Operations.list_overdue_tasks(authorize?: false)

    Enum.count(tasks, fn task ->
      record_once("task_overdue:#{task.id}:#{DateTime.to_iso8601(task.due_at)}", %{
        resource: "task",
        action: "overdue",
        record_id: task.id,
        depth: automation_depth(task),
        data: %{
          "title" => task.title,
          "priority" => Atom.to_string(task.priority),
          "task_type" => Atom.to_string(task.task_type),
          "owner_team_member_id" => task.owner_team_member_id,
          "due_at" => DateTime.to_iso8601(task.due_at),
          "days_overdue" => days_between(task.due_at, DateTime.utc_now())
        }
      })
    end)
  end

  defp sweep_bids_due_soon do
    {:ok, bids} = Procurement.list_bids_due_within(@bid_due_window_days, authorize?: false)

    Enum.count(bids, fn bid ->
      days_until_due = days_between(DateTime.utc_now(), bid.due_at)
      bucket = deadline_bucket(days_until_due)

      record_once(
        "bid_due_soon:#{bid.id}:#{DateTime.to_iso8601(bid.due_at)}:#{bucket}",
        %{
          resource: "bid",
          action: "due_soon",
          record_id: bid.id,
          data: %{
            "title" => bid.title,
            "agency" => bid.agency,
            "status" => Atom.to_string(bid.status),
            "score_tier" => bid.score_tier && Atom.to_string(bid.score_tier),
            "due_at" => DateTime.to_iso8601(bid.due_at),
            "days_until_due" => days_until_due,
            "deadline_bucket" => bucket
          }
        }
      )
    end)
  end

  # Smallest configured bucket the deadline currently falls inside; the
  # dedupe key includes it, so each escalation emits exactly one new event.
  defp deadline_bucket(days_until_due) do
    @deadline_buckets
    |> Enum.reverse()
    |> Enum.find(List.first(@deadline_buckets), &(days_until_due <= &1))
  end

  # Each qualification emits one dynamic episode when it enters its own
  # renewal window. The key includes the expiration date and configured lead
  # time, so ordinary sweeps cannot create duplicate tasks while a renewed or
  # reconfigured qualification starts a fresh episode.
  defp sweep_expiring_qualifications do
    {:ok, qualifications} =
      Company.list_company_qualifications_expiring_within(max_renewal_window(), authorize?: false)

    Enum.count(qualifications, fn qualification ->
      days_until_expiry = Date.diff(qualification.expires_on, Date.utc_today())

      case renewal_bucket(qualification.renewal_lead_days, days_until_expiry) do
        nil ->
          false

        bucket ->
          record_once(
            "qualification_renewal:#{qualification.id}:#{qualification.expires_on}:#{bucket}",
            %{
              resource: "company_qualification",
              action: "expiring",
              record_id: qualification.id,
              data: %{
                "name" => qualification.name,
                "kind" => Atom.to_string(qualification.kind),
                "issuing_authority" => qualification.issuing_authority,
                "identifier" => qualification.identifier,
                "expires_on" => Date.to_iso8601(qualification.expires_on),
                "days_until_expiry" => days_until_expiry,
                "renewal_bucket" => bucket,
                "renewal_lead_days" => qualification.renewal_lead_days,
                "owner_team_member_id" => qualification.owner_team_member_id
              }
            }
          )
      end
    end)
  end

  defp renewal_bucket(lead_days, days_until_expiry) when days_until_expiry <= lead_days,
    do: lead_days

  defp renewal_bucket(_lead_days, _days_until_expiry), do: nil

  defp max_renewal_window do
    {:ok, qualifications} = Company.list_active_company_qualifications(authorize?: false)

    qualifications
    |> Enum.map(& &1.renewal_lead_days)
    |> Enum.max(fn -> 90 end)
  end

  defp record_once(dedupe_key, attrs) do
    case Automation.record_automation_event(
           Map.put(attrs, :dedupe_key, dedupe_key),
           authorize?: false
         ) do
      {:ok, _event} ->
        true

      {:error, error} ->
        if duplicate_key?(error) do
          false
        else
          raise "time sweep failed to record #{dedupe_key}: #{Exception.message(error)}"
        end
    end
  end

  defp duplicate_key?(%Ash.Error.Invalid{} = error),
    do: Exception.message(error) =~ "has already been taken"

  defp duplicate_key?(_error), do: false

  defp automation_depth(%{metadata: %{"automation_depth" => depth}}) when is_integer(depth),
    do: depth

  defp automation_depth(_task), do: 0

  # Both sweeps filter on non-nil due dates, so inputs are always present.
  defp days_between(earlier, later),
    do: DateTime.diff(later, earlier, :second) |> div(86_400)
end
