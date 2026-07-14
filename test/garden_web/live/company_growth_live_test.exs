defmodule GnomeGardenWeb.CompanyGrowthLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Company
  alias GnomeGarden.Operations

  setup do
    case Company.get_primary_company_profile(authorize?: false) do
      {:ok, _profile} ->
        :ok

      {:error, _none} ->
        {:ok, _profile} =
          Company.create_company_profile(%{key: "primary", name: "Gnome Automation"})

        :ok
    end
  end

  test "ideas are captured, advanced, and delivered from the workspace", %{conn: conn} do
    {:ok, index_view, _html} = live(conn, ~p"/company/growth")

    index_view
    |> form("#growth-capture-form", %{
      "form" => %{"title" => "DIR public works registration", "category" => "registration"}
    })
    |> render_submit()

    assert render(index_view) =~ "DIR public works registration"

    {:ok, [initiative]} = Company.list_growth_initiatives(authorize?: false)
    assert initiative.status == :idea

    {:ok, show_view, show_html} = live(conn, ~p"/company/growth/#{initiative}")
    assert show_html =~ "No evidence linked"

    show_view
    |> element(~s(button[phx-click="transition"][phx-value-action="plan"]))
    |> render_click()

    {:ok, planned} = Company.get_growth_initiative(initiative.id, authorize?: false)
    assert planned.status == :planned

    # Task entry from the initiative prefills the link back.
    assert render(show_view) =~ "company_growth_initiative_id=#{initiative.id}"
  end

  test "qualification registry creates and activates through the UI", %{conn: conn} do
    {:ok, form_view, _html} = live(conn, ~p"/company/qualifications/new")

    form_view
    |> form("#qualification-form", %{
      "form" => %{
        "kind" => "license",
        "name" => "CSLB C-7",
        "issuing_authority" => "CSLB",
        "identifier" => "123456",
        "renewal_lead_days" => "60",
        "unlocks" => "low-voltage, controls",
        "details" => ~s({"classification": "C-7"})
      }
    })
    |> render_submit()

    {:ok, [qualification]} = Company.list_company_qualifications(authorize?: false)
    assert qualification.unlocks == ["low-voltage", "controls"]
    assert qualification.details["classification"] == "C-7"

    {:ok, index_view, html} = live(conn, ~p"/company/qualifications")
    assert html =~ "CSLB C-7"

    index_view
    |> element(~s(button[phx-click="activate"][phx-value-id="#{qualification.id}"]))
    |> render_click()

    {:ok, active} = Company.get_company_qualification(qualification.id, authorize?: false)
    assert active.status == :active
  end

  test "growth tasks surface in My Tasks with the initiative as context", %{
    conn: conn,
    current_team_member: team_member
  } do
    {:ok, profile} = Company.get_primary_company_profile(authorize?: false)

    {:ok, initiative} =
      Company.create_growth_initiative(%{
        company_profile_id: profile.id,
        title: "SB certification",
        category: :certification
      })

    {:ok, _task} =
      Operations.create_task(%{
        title: "Gather DGS documents",
        company_growth_initiative_id: initiative.id,
        owner_team_member_id: team_member.id
      })

    {:ok, _view, html} = live(conn, ~p"/operations/my-tasks")
    assert html =~ "Gather DGS documents"
    assert html =~ "SB certification"
  end
end
