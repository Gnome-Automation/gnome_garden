defmodule GnomeGarden.Repo.Migrations.AddTeamMembersForOperatorWork do
  @moduledoc """
  Adds durable team members and moves execution/finance operator fields away
  from raw auth users.
  """

  use Ecto.Migration

  def up do
    create table(:team_members, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :display_name, :text, null: false
      add :role, :text, null: false, default: "operator"
      add :status, :text, null: false, default: "active"
      add :capacity_hours_per_week, :bigint
      add :notes, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "team_members_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :person_id,
          references(:people,
            column: :id,
            name: "team_members_person_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nilify_all
          )
    end

    create unique_index(:team_members, [:user_id], name: "team_members_unique_user_index")

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

    retarget_user_reference(
      :execution_work_items,
      :owner_user_id,
      :owner_team_member_id,
      "execution_work_items_owner_user_id_fkey",
      "execution_work_items_owner_team_member_id_fkey",
      null: true
    )

    retarget_user_reference(
      :finance_time_entries,
      :member_user_id,
      :member_team_member_id,
      "finance_time_entries_member_user_id_fkey",
      "finance_time_entries_member_team_member_id_fkey",
      null: false
    )

    retarget_user_reference(
      :finance_time_entries,
      :approved_by_user_id,
      :approved_by_team_member_id,
      "finance_time_entries_approved_by_user_id_fkey",
      "finance_time_entries_approved_by_team_member_id_fkey",
      null: true
    )

    retarget_user_reference(
      :execution_assignments,
      :assigned_user_id,
      :assigned_team_member_id,
      "execution_assignments_assigned_user_id_fkey",
      "execution_assignments_assigned_team_member_id_fkey",
      null: false
    )

    retarget_user_reference(
      :execution_assignments,
      :assigned_by_user_id,
      :assigned_by_team_member_id,
      "execution_assignments_assigned_by_user_id_fkey",
      "execution_assignments_assigned_by_team_member_id_fkey",
      null: true
    )

    retarget_user_reference(
      :finance_expenses,
      :incurred_by_user_id,
      :incurred_by_team_member_id,
      "finance_expenses_incurred_by_user_id_fkey",
      "finance_expenses_incurred_by_team_member_id_fkey",
      null: false
    )

    retarget_user_reference(
      :finance_expenses,
      :approved_by_user_id,
      :approved_by_team_member_id,
      "finance_expenses_approved_by_user_id_fkey",
      "finance_expenses_approved_by_team_member_id_fkey",
      null: true
    )
  end

  def down do
    retarget_team_member_reference(
      :finance_expenses,
      :approved_by_team_member_id,
      :approved_by_user_id,
      "finance_expenses_approved_by_team_member_id_fkey",
      "finance_expenses_approved_by_user_id_fkey",
      null: true
    )

    retarget_team_member_reference(
      :finance_expenses,
      :incurred_by_team_member_id,
      :incurred_by_user_id,
      "finance_expenses_incurred_by_team_member_id_fkey",
      "finance_expenses_incurred_by_user_id_fkey",
      null: false
    )

    retarget_team_member_reference(
      :execution_assignments,
      :assigned_by_team_member_id,
      :assigned_by_user_id,
      "execution_assignments_assigned_by_team_member_id_fkey",
      "execution_assignments_assigned_by_user_id_fkey",
      null: true
    )

    retarget_team_member_reference(
      :execution_assignments,
      :assigned_team_member_id,
      :assigned_user_id,
      "execution_assignments_assigned_team_member_id_fkey",
      "execution_assignments_assigned_user_id_fkey",
      null: false
    )

    retarget_team_member_reference(
      :finance_time_entries,
      :approved_by_team_member_id,
      :approved_by_user_id,
      "finance_time_entries_approved_by_team_member_id_fkey",
      "finance_time_entries_approved_by_user_id_fkey",
      null: true
    )

    retarget_team_member_reference(
      :finance_time_entries,
      :member_team_member_id,
      :member_user_id,
      "finance_time_entries_member_team_member_id_fkey",
      "finance_time_entries_member_user_id_fkey",
      null: false
    )

    retarget_team_member_reference(
      :execution_work_items,
      :owner_team_member_id,
      :owner_user_id,
      "execution_work_items_owner_team_member_id_fkey",
      "execution_work_items_owner_user_id_fkey",
      null: true
    )

    drop_if_exists unique_index(:team_members, [:user_id], name: "team_members_unique_user_index")
    drop table(:team_members)
  end

  defp retarget_user_reference(
         table_name,
         old_column,
         new_column,
         old_constraint,
         new_constraint,
         opts
       ) do
    drop_if_exists constraint(table_name, old_constraint)
    rename table(table_name), old_column, to: new_column

    alter table(table_name) do
      modify new_column,
             references(:team_members,
               column: :id,
               name: new_constraint,
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             ),
             null: opts[:null]
    end
  end

  defp retarget_team_member_reference(
         table_name,
         old_column,
         new_column,
         old_constraint,
         new_constraint,
         opts
       ) do
    drop_if_exists constraint(table_name, old_constraint)
    rename table(table_name), old_column, to: new_column

    alter table(table_name) do
      modify new_column,
             references(:users,
               column: :id,
               name: new_constraint,
               type: :uuid,
               prefix: "public",
               on_delete: :nilify_all
             ),
             null: opts[:null]
    end
  end
end
