defmodule GnomeGarden.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GnomeGarden.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias GnomeGarden.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import GnomeGarden.DataCase
    end
  end

  setup tags do
    GnomeGarden.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    reset_test_storage()
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(GnomeGarden.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    seed_reference_data()
  end

  # System reference data that exists in every environment. The ledger chart of
  # accounts is required by GL-posting changes (invoice issue, payment apply),
  # so it must be present for tests that exercise those flows.
  defp seed_reference_data do
    GnomeGarden.Ledger.DefaultChartOfAccounts.ensure_defaults()
  end

  defp reset_test_storage do
    if Code.ensure_loaded?(AshStorage.Service.Test) do
      AshStorage.Service.Test.reset!()
    end
  end

  def activate_exa_program_source!(discovery_program, attrs \\ %{}) do
    discovery_program =
      case discovery_program.status do
        :active -> discovery_program
        _not_active -> GnomeGarden.Commercial.activate_discovery_program!(discovery_program)
      end

    acquisition_program =
      GnomeGarden.Acquisition.get_program_by_discovery_program!(discovery_program.id)

    source =
      GnomeGarden.Acquisition.create_source!(
        %{
          external_ref: "provider:exa:search",
          name: "Exa Search",
          url: "https://api.exa.ai/search",
          source_family: :discovery,
          source_kind: :directory,
          status: :active,
          enabled: true,
          scan_strategy: :deterministic
        },
        upsert?: true,
        upsert_identity: :unique_external_ref,
        upsert_fields: []
      )

    policy =
      GnomeGarden.Acquisition.create_program_source!(%{
        program_id: acquisition_program.id,
        source_id: source.id
      })

    defaults = %{
      query_templates:
        case discovery_program.search_terms do
          [_ | _] = search_terms -> search_terms
          [] -> ["#{discovery_program.name} commercial company search"]
        end,
      cadence_minutes: max(discovery_program.cadence_hours, 1) * 60
    }

    policy
    |> GnomeGarden.Acquisition.update_program_source_policy!(Map.merge(defaults, attrs))
    |> GnomeGarden.Acquisition.activate_program_source!()
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user_with_password(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
