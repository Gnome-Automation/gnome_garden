defmodule GnomeGarden.Repo.Migrations.AlignOperatorResponsibilityToTeamMembers do
  @moduledoc """
  Moves remaining business responsibility fields from auth users to team members.
  """

  use Ecto.Migration

  @retargets [
    {:acquisition_programs, :owner_user_id, :owner_team_member_id,
     "acquisition_programs_owner_user_id_fkey", "acquisition_programs_owner_team_member_id_fkey"},
    {:commercial_agreements, :owner_user_id, :owner_team_member_id,
     "commercial_agreements_owner_user_id_fkey",
     "commercial_agreements_owner_team_member_id_fkey"},
    {:commercial_pursuits, :owner_user_id, :owner_team_member_id,
     "commercial_pursuits_owner_user_id_fkey", "commercial_pursuits_owner_team_member_id_fkey"},
    {:commercial_discovery_programs, :owner_user_id, :owner_team_member_id,
     "commercial_discovery_programs_owner_user_id_fkey",
     "commercial_discovery_programs_owner_team_member_id_fkey"},
    {:execution_projects, :manager_user_id, :manager_team_member_id,
     "execution_projects_manager_user_id_fkey", "execution_projects_manager_team_member_id_fkey"},
    {:commercial_discovery_records, :owner_user_id, :owner_team_member_id,
     "commercial_discovery_records_owner_user_id_fkey",
     "commercial_discovery_records_owner_team_member_id_fkey"},
    {:execution_work_orders, :requested_by_user_id, :requested_by_team_member_id,
     "execution_work_orders_requested_by_user_id_fkey",
     "execution_work_orders_requested_by_team_member_id_fkey"},
    {:execution_work_orders, :assigned_user_id, :assigned_team_member_id,
     "execution_work_orders_assigned_user_id_fkey",
     "execution_work_orders_assigned_team_member_id_fkey"},
    {:commercial_signals, :owner_user_id, :owner_team_member_id,
     "commercial_signals_owner_user_id_fkey", "commercial_signals_owner_team_member_id_fkey"},
    {:execution_maintenance_plans, :assigned_user_id, :assigned_team_member_id,
     "execution_maintenance_plans_assigned_user_id_fkey",
     "execution_maintenance_plans_assigned_team_member_id_fkey"},
    {:execution_service_tickets, :owner_user_id, :owner_team_member_id,
     "execution_service_tickets_owner_user_id_fkey",
     "execution_service_tickets_owner_team_member_id_fkey"},
    {:commercial_change_orders, :owner_user_id, :owner_team_member_id,
     "commercial_change_orders_owner_user_id_fkey",
     "commercial_change_orders_owner_team_member_id_fkey"},
    {:people, :owner_user_id, :owner_team_member_id, "people_owner_user_id_fkey",
     "people_owner_team_member_id_fkey"},
    {:commercial_proposals, :owner_user_id, :owner_team_member_id,
     "commercial_proposals_owner_user_id_fkey", "commercial_proposals_owner_team_member_id_fkey"}
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
