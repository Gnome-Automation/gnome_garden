defmodule GnomeGardenWeb.ProcurementTargetingLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial.CompanyProfileLearning

  test "targeting live shows learned excludes and recent feedback", %{conn: conn} do
    {:ok, _result} =
      CompanyProfileLearning.add_learned_excludes(
        company_profile_mode: "industrial_plus_software",
        exclude_terms: ["cctv", "video surveillance"]
      )

    {:ok, view, _html} = live(conn, ~p"/procurement/targeting")

    assert render(view) =~ "Targeting Controls"
    assert has_element?(view, "#learned-exclude")
    assert render(view) =~ "cctv"
    assert render(view) =~ "video surveillance"
    assert has_element?(view, "#procurement-targeting-form")
  end

  test "operator can remove a learned exclusion from the page", %{conn: conn} do
    {:ok, _result} =
      CompanyProfileLearning.add_learned_excludes(
        company_profile_mode: "industrial_plus_software",
        exclude_terms: ["cctv", "video surveillance"]
      )

    {:ok, view, _html} = live(conn, ~p"/procurement/targeting")

    render_click(element(view, ~s(button[phx-click="remove_exclude"][phx-value-term="cctv"])))

    html = render(view)
    refute html =~ ~s(phx-value-term="cctv")
    assert html =~ "video surveillance"
  end
end
