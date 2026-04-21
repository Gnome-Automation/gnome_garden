defmodule GnomeGarden.Acquisition.Changes.RequirePromotionReady do
  @moduledoc false

  use Ash.Resource.Change

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.PromotionRules

  @impl true
  def change(changeset, _opts, context) do
    case load_finding(changeset.data.id, context.actor) do
      {:ok, finding} ->
        case PromotionRules.blockers(finding) do
          [] ->
            changeset

          blockers ->
            Ash.Changeset.add_error(
              changeset,
              field: :status,
              message: "finding is not ready for promotion: #{Enum.join(blockers, " ")}"
            )
        end

      {:error, error} ->
        Ash.Changeset.add_error(
          changeset,
          field: :status,
          message: "could not verify promotion readiness: #{inspect(error)}"
        )
    end
  end

  defp load_finding(nil, _actor), do: {:error, :missing_finding_id}

  defp load_finding(id, actor) do
    Acquisition.get_finding(id, actor: actor, load: PromotionRules.required_load())
  end
end
