defmodule GnomeGarden.Commercial.Changes.CreateAgreementFromProposal do
  @moduledoc """
  Populates a new agreement from an accepted proposal.
  """

  use Ash.Resource.Change

  alias GnomeGarden.Commercial

  @impl true
  def change(changeset, _opts, _context) do
    proposal_id = Ash.Changeset.get_argument(changeset, :proposal_id)

    case load_proposal(proposal_id) do
      {:ok, proposal} ->
        if proposal.status == :accepted do
          apply_defaults(changeset, proposal)
        else
          Ash.Changeset.add_error(changeset,
            field: :proposal_id,
            message: "proposal must be accepted before creating an agreement"
          )
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :proposal_id,
          message: "could not load proposal: %{error}",
          vars: %{error: inspect(error)}
        )
    end
  end

  defp load_proposal(nil), do: {:error, :missing_proposal_id}

  defp load_proposal(proposal_id) do
    Commercial.get_proposal(proposal_id, load: [:total_amount])
  end

  defp apply_defaults(changeset, proposal) do
    changeset
    |> set_if_unchanged(:pursuit_id, proposal.pursuit_id)
    |> set_if_unchanged(:proposal_id, proposal.id)
    |> set_if_unchanged(:organization_id, proposal.organization_id)
    |> set_if_unchanged(:site_id, proposal.site_id)
    |> set_if_unchanged(:managed_system_id, proposal.managed_system_id)
    |> set_if_unchanged(:owner_user_id, proposal.owner_user_id)
    |> set_if_unchanged(:reference_number, proposal.proposal_number)
    |> set_if_unchanged(:name, proposal.name)
    |> set_if_unchanged(:agreement_type, infer_agreement_type(proposal.delivery_model))
    |> set_if_unchanged(:billing_model, proposal.pricing_model)
    |> set_if_unchanged(:currency_code, proposal.currency_code)
    |> set_if_unchanged(:contract_value, proposal.total_amount)
    |> set_if_unchanged(:notes, proposal.notes)
  end

  defp set_if_unchanged(changeset, attribute, value) do
    if Ash.Changeset.changing_attribute?(changeset, attribute) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, attribute, value)
    end
  end

  defp infer_agreement_type(:project), do: :project
  defp infer_agreement_type(:service), do: :service
  defp infer_agreement_type(:maintenance), do: :maintenance
  defp infer_agreement_type(:retainer), do: :retainer
  defp infer_agreement_type(:mixed), do: :other
  defp infer_agreement_type(_), do: :other
end
