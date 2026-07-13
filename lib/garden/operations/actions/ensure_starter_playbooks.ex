defmodule GnomeGarden.Operations.Actions.EnsureStarterPlaybooks do
  @moduledoc """
  Idempotently installs the starter playbooks as editable database records.

  Existing playbooks are left untouched — operators own their edits — so
  re-running only fills gaps. Content lives here solely as installation
  defaults; the database remains the source of truth.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Operations

  @starters [
    {"New bid review", "Standard review loop for a freshly qualified bid.",
     [
       {1, "Review bid fit against company profile", :review, :high, 1, :applier},
       {2, "Check insurance, bond, and license requirements", :research, :normal, 2, :unassigned},
       {3, "Bid / no-bid decision", :review, :high, 3, :unassigned}
     ]},
    {"Pursuit qualification", "Qualify a pursuit before committing proposal effort.",
     [
       {1, "Qualify budget and timeline with the buyer", :call, :normal, 2, :applier},
       {2, "Identify the decision maker and influencers", :research, :normal, 2, :unassigned},
       {3, "Schedule site walk", :call, :normal, 5, :unassigned}
     ]},
    {"Proposal preparation", "Draft, review, and submit a proposal.",
     [
       {1, "Draft scope and pricing", :proposal, :high, 3, :applier},
       {2, "Internal proposal review", :review, :normal, 4, :unassigned},
       {3, "Submit proposal", :proposal, :urgent, 5, :unassigned}
     ]},
    {"Project kickoff", "Everything between agreement and first day on site.",
     [
       {1, "Pull permits", :other, :high, 3, :unassigned},
       {2, "Order materials", :other, :normal, 2, :unassigned},
       {3, "Schedule crew", :call, :normal, 2, :unassigned},
       {4, "Client kickoff call", :call, :normal, 1, :applier}
     ]},
    {"Source remediation", "Bring a failing procurement source back to healthy.",
     [
       {1, "Verify and fix source credentials", :source_cleanup, :high, 1, :applier},
       {2, "Re-run scan and confirm findings flow", :source_cleanup, :normal, 2, :unassigned}
     ]},
    {"Customer onboarding", "Vendor packet and access setup for a new customer.",
     [
       {1, "Collect vendor packet requirements", :email, :normal, 2, :applier},
       {2, "Submit W-9 and insurance certificates", :finance, :normal, 3, :unassigned},
       {3, "Confirm portal and billing access", :other, :normal, 4, :unassigned}
     ]}
  ]

  @impl true
  def run(_input, _opts, context) do
    opts = [actor: context.actor, authorize?: false]

    results =
      Enum.map(@starters, fn {name, description, steps} ->
        case Operations.get_playbook_by_name(name, opts) do
          {:ok, _existing} -> {name, :existing}
          {:error, _not_found} -> {name, install(name, description, steps, opts)}
        end
      end)

    {:ok, Map.new(results)}
  end

  defp install(name, description, steps, opts) do
    with {:ok, playbook} <-
           Operations.create_playbook(%{name: name, description: description}, opts),
         :ok <- install_steps(playbook, steps, opts) do
      :created
    end
  end

  defp install_steps(playbook, steps, opts) do
    Enum.reduce_while(steps, :ok, fn {position, title, task_type, priority, offset, strategy},
                                     :ok ->
      case Operations.create_playbook_step(
             %{
               playbook_id: playbook.id,
               position: position,
               title: title,
               task_type: task_type,
               priority: priority,
               due_offset_days: offset,
               assignee_strategy: strategy
             },
             opts
           ) do
        {:ok, _step} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
