defmodule GnomeGardenWeb.AdminAccess do
  @moduledoc "Authorization helper for the small set of humans allowed into Garden."

  alias GnomeGarden.Operations

  def admin_team_member(nil), do: {:error, :not_signed_in}

  def admin_team_member(%{id: user_id} = user) do
    case Operations.get_team_member_by_user(user_id, actor: user) do
      {:ok, %{role: :admin, status: :active} = team_member} -> {:ok, team_member}
      {:ok, _team_member} -> {:error, :not_admin}
      {:error, _error} -> {:error, :not_admin}
    end
  end

  def admin?({:ok, _team_member}), do: true
  def admin?(_result), do: false
end
