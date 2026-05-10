defmodule GnomeGarden.Repo.Migrations.AlignAgentOperatorOwnership do
  @moduledoc """
  Separates agent runtime audit identity from operator ownership.
  """

  use Ecto.Migration

  def up do
    seed_missing_team_members()

    alter table(:agent_runs) do
      add :requested_by_team_member_id,
          references(:team_members,
            column: :id,
            name: "agent_runs_requested_by_team_member_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    execute("""
    UPDATE agent_runs
    SET requested_by_team_member_id = team_members.id
    FROM team_members
    WHERE agent_runs.requested_by_user_id = team_members.user_id
    """)

    drop_if_exists constraint(:agent_deployments, "agent_deployments_owner_user_id_fkey")
    rename table(:agent_deployments), :owner_user_id, to: :owner_team_member_id

    execute("""
    UPDATE agent_deployments
    SET owner_team_member_id = team_members.id
    FROM team_members
    WHERE agent_deployments.owner_team_member_id = team_members.user_id
    """)

    alter table(:agent_deployments) do
      modify :owner_team_member_id,
             references(:team_members,
               column: :id,
               name: "agent_deployments_owner_team_member_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             )
    end
  end

  def down do
    drop constraint(:agent_deployments, "agent_deployments_owner_team_member_id_fkey")
    rename table(:agent_deployments), :owner_team_member_id, to: :owner_user_id

    execute("""
    UPDATE agent_deployments
    SET owner_user_id = team_members.user_id
    FROM team_members
    WHERE agent_deployments.owner_user_id = team_members.id
    """)

    alter table(:agent_deployments) do
      modify :owner_user_id,
             references(:users,
               column: :id,
               name: "agent_deployments_owner_user_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             )
    end

    drop constraint(:agent_runs, "agent_runs_requested_by_team_member_id_fkey")

    alter table(:agent_runs) do
      remove :requested_by_team_member_id
    end
  end

  defp seed_missing_team_members do
    execute("""
    INSERT INTO team_members (id, user_id, display_name, role, status, inserted_at, updated_at)
    SELECT
      users.id,
      users.id,
      COALESCE(NULLIF(split_part(users.email::text, '@', 1), ''), 'Operator'),
      'operator',
      'active',
      (now() AT TIME ZONE 'utc'),
      (now() AT TIME ZONE 'utc')
    FROM users
    ON CONFLICT (user_id) DO NOTHING
    """)
  end
end
