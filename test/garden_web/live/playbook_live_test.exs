defmodule GnomeGardenWeb.PlaybookLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "playbooks are managed end to end from the UI", %{conn: conn} do
    {:ok, index_view, _html} = live(conn, ~p"/operations/playbooks")

    index_view |> element("#install-starters") |> render_click()
    assert render(index_view) =~ "New bid review"

    {:ok, playbook} = Operations.get_playbook_by_name("New bid review", authorize?: false)
    {:ok, show_view, show_html} = live(conn, ~p"/operations/playbooks/#{playbook}")

    assert show_html =~ "Review bid fit against company profile"

    show_view
    |> form("#playbook-step-form", %{
      "form" => %{"title" => "Extra diligence step", "position" => "4"}
    })
    |> render_submit()

    assert render(show_view) =~ "Extra diligence step"
  end

  test "applying a playbook from the pursuit page creates its task set", %{conn: conn} do
    {:ok, _results} = Operations.ensure_starter_playbooks(authorize?: false)
    {:ok, playbook} = Operations.get_playbook_by_name("Pursuit qualification", authorize?: false)

    {:ok, organization} =
      Operations.create_organization(%{
        name: "Playbook Apply Org",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, pursuit} =
      Commercial.create_pursuit(%{
        organization_id: organization.id,
        name: "Playbook apply pursuit",
        pursuit_type: :bid_response
      })

    {:ok, view, html} = live(conn, ~p"/commercial/pursuits/#{pursuit}")
    assert html =~ "No playbook runs"

    view
    |> form("#apply-playbook-form", %{"playbook_id" => playbook.id})
    |> render_submit()

    html = render(view)
    assert html =~ "Applied playbook: Pursuit qualification"
    assert html =~ "0 of 3 done"

    assert {:ok, [run]} = Operations.list_playbook_runs_for_pursuit(pursuit.id)
    run = Ash.load!(run, [:tasks], authorize?: false)
    assert length(run.tasks) == 3
    assert Enum.all?(run.tasks, &(&1.pursuit_id == pursuit.id))
  end
end
