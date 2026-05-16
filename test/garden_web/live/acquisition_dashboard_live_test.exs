defmodule GnomeGardenWeb.AcquisitionDashboardLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial

  setup :register_and_log_in_user

  test "dashboard renders the seven-day operating path", %{conn: conn} do
    previous_sam_key = System.get_env("SAM_GOV_API_KEY")
    System.put_env("SAM_GOV_API_KEY", "test-sam-key")

    on_exit(fn ->
      restore_env("SAM_GOV_API_KEY", previous_sam_key)
    end)

    {:ok, view, html} = live(conn, ~p"/acquisition/dashboard")

    assert html =~ "Lead System Dashboard"
    assert html =~ "Next Objective"
    assert html =~ "Runtime Evidence"
    assert html =~ "Learning Loop"

    html =
      view
      |> element("button", "Seed Pilot Defaults")
      |> render_click()

    assert html =~ "Seven Day Food Plant Automation Sweep"
    assert html =~ "SAM.gov Contract Opportunities"
  end

  test "dashboard links to reviewable findings", %{conn: conn} do
    {:ok, program} =
      Commercial.create_discovery_program(%{
        name: "Dashboard Discovery Program",
        target_regions: ["oc"],
        target_industries: ["manufacturing"]
      })

    {:ok, _program} = Commercial.activate_discovery_program(program)

    {:ok, record} =
      Commercial.create_discovery_record(%{
        discovery_program_id: program.id,
        name: "Dashboard Automation Lead",
        website: "https://dashboard-lead.example.com",
        fit_score: 84,
        intent_score: 76,
        notes: "Hiring controls technicians and expanding production capacity."
      })

    {:ok, finding} =
      Acquisition.get_finding_by_source_discovery_record(record.id)

    {:ok, _view, html} = live(conn, ~p"/acquisition/dashboard")

    assert html =~ "Dashboard Automation Lead"
    assert html =~ ~s(href="/acquisition/findings/#{finding.id}")
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
