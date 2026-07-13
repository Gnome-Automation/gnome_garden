defmodule GnomeGarden.Automation.Changes.ProcessEvent do
  @moduledoc """
  Evaluates published rules against an event and marks it processed.

  Runs in the event's `:process` update action so both the AshOban sweep and
  direct calls share one path. Each matching rule gets an idempotent
  `Automation.Run`; failures are recorded on the run and summarized on the
  event without blocking other rules.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Automation.Evaluator

  @max_depth 3

  @impl true
  def change(changeset, _opts, _context) do
    event = changeset.data

    if event.depth >= @max_depth do
      changeset
      |> Ash.Changeset.force_change_attribute(:processed_at, DateTime.utc_now())
      |> Ash.Changeset.force_change_attribute(
        :error,
        "recursion depth #{event.depth} reached the cap of #{@max_depth}; rules skipped"
      )
    else
      case Evaluator.evaluate(event) do
        :ok ->
          Ash.Changeset.force_change_attribute(changeset, :processed_at, DateTime.utc_now())

        {:error, summary} ->
          changeset
          |> Ash.Changeset.force_change_attribute(:processed_at, DateTime.utc_now())
          |> Ash.Changeset.force_change_attribute(:error, summary)
      end
    end
  end
end
