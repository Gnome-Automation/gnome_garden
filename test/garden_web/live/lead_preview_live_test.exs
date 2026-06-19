defmodule GnomeGardenWeb.Acquisition.LeadPreviewLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Search.Exa

  setup :register_and_log_in_user

  test "mounts and renders the search form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/acquisition/lead-preview")
    assert html =~ "Lead Preview"
    assert html =~ "Run preview"
    assert html =~ "Industries"
  end

  test "runs a preview and promotes a company candidate into the review queue", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/acquisition/lead-preview")

    domain = "newco-#{System.unique_integer([:positive])}.example.com"

    # The LiveView runs Exa in its own process; allow it to use this test's stub.
    Req.Test.stub(Exa, fn conn ->
      Req.Test.json(conn, %{
        "costDollars" => %{"total" => 0.004},
        "results" => [%{"title" => "NewCo Manufacturing", "url" => "https://#{domain}", "publishedDate" => nil}]
      })
    end)

    Req.Test.allow(Exa, self(), view.pid)

    # Use a raw term (company intent) so the candidate is promotable, not a signal page.
    html =
      view
      |> form("#lead-preview-form", %{
        "preview" => %{
          "industries" => "",
          "regions" => "",
          "terms" => "newco manufacturing",
          "since" => "",
          "max_queries" => "1",
          "ceiling" => "1.0",
          "program_id" => ""
        }
      })
      |> render_submit()

    assert html =~ "NewCo Manufacturing"
    assert html =~ "Promotable"

    render_click(view, "promote", %{"index" => "0"})

    assert {:ok, _record} = Commercial.get_discovery_record_by_website_domain(domain)
  end
end
