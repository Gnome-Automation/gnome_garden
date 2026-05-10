defmodule GnomeGarden.Repo.Migrations.AlignRemainingOperatorOwnership do
  @moduledoc """
  Moves the last business assignment fields from auth users to team members.
  """

  use Ecto.Migration

  @retargets [
    {:tasks, :owner_id, :owner_team_member_id, "tasks_owner_id_fkey",
     "tasks_owner_team_member_id_fkey"},
    {:research_requests, :assigned_to_id, :assigned_team_member_id,
     "research_requests_assigned_to_id_fkey", "research_requests_assigned_team_member_id_fkey"},
    {:bids, :owner_id, :owner_team_member_id, "bids_owner_id_fkey",
     "bids_owner_team_member_id_fkey"},
    {:activities, :owner_id, :owner_team_member_id, "activities_owner_id_fkey",
     "activities_owner_team_member_id_fkey"}
  ]

  def up do
    seed_missing_team_members()

    Enum.each(@retargets, fn {table_name, old_column, new_column, old_constraint, new_constraint} ->
      retarget_user_reference(table_name, old_column, new_column, old_constraint, new_constraint)
    end)
  end

  def down do
    @retargets
    |> Enum.reverse()
    |> Enum.each(fn {table_name, old_column, new_column, old_constraint, new_constraint} ->
      retarget_team_member_reference(
        table_name,
        new_column,
        old_column,
        new_constraint,
        old_constraint
      )
    end)
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

  defp retarget_user_reference(table_name, old_column, new_column, old_constraint, new_constraint) do
    drop_if_exists constraint(table_name, old_constraint)
    rename table(table_name), old_column, to: new_column

    execute("""
    UPDATE #{table_name}
    SET #{new_column} = team_members.id
    FROM team_members
    WHERE #{table_name}.#{new_column} = team_members.user_id
    """)

    alter table(table_name) do
      modify new_column,
             references(:team_members,
               column: :id,
               name: new_constraint,
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             )
    end
  end

  defp retarget_team_member_reference(
         table_name,
         old_column,
         new_column,
         old_constraint,
         new_constraint
       ) do
    drop_if_exists constraint(table_name, old_constraint)
    rename table(table_name), old_column, to: new_column

    execute("""
    UPDATE #{table_name}
    SET #{new_column} = team_members.user_id
    FROM team_members
    WHERE #{table_name}.#{new_column} = team_members.id
    """)

    alter table(table_name) do
      modify new_column,
             references(:users,
               column: :id,
               name: new_constraint,
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             )
    end
  end
end
