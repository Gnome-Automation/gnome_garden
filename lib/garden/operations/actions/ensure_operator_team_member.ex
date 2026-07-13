defmodule GnomeGarden.Operations.Actions.EnsureOperatorTeamMember do
  @moduledoc """
  Idempotently ensures an active operator TeamMember for a registered user.

  Never invents credentials: when no user is registered for the email, the
  action fails and the person must complete the normal registration flow
  first.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations

  @impl true
  def run(input, _opts, context) do
    email = Ash.ActionInput.get_argument(input, :email)
    display_name = Ash.ActionInput.get_argument(input, :display_name)
    opts = [actor: context.actor, authorize?: false]

    case Accounts.get_user_by_email(email, opts) do
      {:ok, user} ->
        ensure_member(user, display_name, opts)

      {:error, _not_found} ->
        {:error,
         "No registered user for #{email}. Complete registration through the normal " <>
           "sign-up flow first; this action never creates credentials."}
    end
  end

  defp ensure_member(user, display_name, opts) do
    case Operations.get_team_member_by_user(user.id, opts) do
      {:ok, member} ->
        if member.status == :active and member.display_name == display_name do
          {:ok, member}
        else
          Operations.update_team_member(
            member,
            %{status: :active, display_name: display_name},
            opts
          )
        end

      {:error, _not_found} ->
        Operations.create_team_member(
          %{
            user_id: user.id,
            display_name: display_name,
            role: :operator,
            status: :active
          },
          opts
        )
    end
  end
end
