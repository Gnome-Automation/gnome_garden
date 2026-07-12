defmodule GnomeGarden.Acquisition.Actions.VerifyLeadPreviewRun do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Acquisition.LeadCandidateVerifier

  @impl true
  def run(input, _opts, context) do
    input
    |> Ash.ActionInput.get_argument(:lead_preview_run_id)
    |> LeadCandidateVerifier.verify_run(actor: context.actor)
  end
end
