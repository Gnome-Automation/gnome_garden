defmodule GnomeGarden.Procurement.SourceInspectorTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement

  defmodule FakeBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://example.com/source",
         title: "Source Home",
         text: "Bid opportunities and documents",
         headings: ["Bid Opportunities"],
         forms: [],
         links: [
           %{"href" => "https://example.com/source/bids/1", "text" => "Bid 1"},
           %{"href" => "https://example.com/source/rfp.pdf", "text" => "RFP PDF"}
         ]
       }}
    end
  end

  defmodule FakeLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://example.com/account/login",
         title: "Vendor Login",
         text: "Sign in to continue",
         headings: ["Vendor Login"],
         forms: [
           %{
             "action" => "https://example.com/account/login",
             "method" => "post",
             "text" => "Username Password Sign in",
             "inputs" => [
               %{"type" => "text", "name" => "username", "placeholder" => "Username"},
               %{"type" => "password", "name" => "password", "placeholder" => "Password"}
             ],
             "buttons" => ["Sign in"]
           }
         ],
         links: []
       }}
    end
  end

  defmodule FakePublicHeaderLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.bidnetdirect.com/california/example",
         title: "Example BidNet",
         text: "Open solicitations and bid search",
         headings: ["Bid Search"],
         forms: [
           %{
             "action" => "https://www.bidnetdirect.com/public/authentication/login",
             "method" => "post",
             "text" => "Email Password Login",
             "inputs" => [
               %{"type" => "text", "name" => "email"},
               %{"type" => "password", "name" => "password"}
             ],
             "buttons" => ["Login"]
           }
         ],
         links: [
           %{"href" => "https://www.bidnetdirect.com/california", "text" => "Bid Search"},
           %{
             "href" => "https://www.bidnetdirect.com/california/example/open-bids",
             "text" => "Open bids"
           }
         ]
       }}
    end
  end

  defmodule FakePublicJobBoardLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.example.com/jobs",
         title: "Public Jobs",
         text: "Search jobs and create an account",
         headings: ["Public Jobs"],
         forms: [
           %{
             "action" => "/login",
             "method" => "post",
             "text" => "Username Password Login",
             "inputs" => [
               %{"type" => "text", "name" => "username"},
               %{"type" => "password", "name" => "password"}
             ],
             "buttons" => ["Login"]
           }
         ],
         links: [%{"href" => "https://www.example.com/jobs", "text" => "Search jobs"}]
       }}
    end
  end

  defmodule FakePublicDirectoryLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.example.com/directory",
         title: "Integrator Directory",
         text: "Find an integrator and member list",
         headings: ["Integrator Directory"],
         forms: [
           %{
             "action" => "/login",
             "method" => "post",
             "text" => "Username Password Login",
             "inputs" => [
               %{"type" => "text", "name" => "username"},
               %{"type" => "password", "name" => "password"}
             ],
             "buttons" => ["Login"]
           }
         ],
         links: [
           %{
             "href" => "https://www.example.com/find-an-integrator",
             "text" => "Find an Integrator"
           },
           %{"href" => "https://www.example.com/member-list", "text" => "Member List"}
         ]
       }}
    end
  end

  defmodule FakePublicForumLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.example.com/forums",
         title: "Automation Community",
         text: "Automation engineering community",
         headings: ["Community"],
         forms: [
           %{
             "action" => "/login",
             "method" => "post",
             "text" => "Username Password Login",
             "inputs" => [
               %{"type" => "text", "name" => "username"},
               %{"type" => "password", "name" => "password"}
             ],
             "buttons" => ["Login"]
           }
         ],
         links: [
           %{"href" => "https://www.example.com/latest/hmi-scada", "text" => "HMIs & SCADA"},
           %{"href" => "https://www.example.com/forums", "text" => "Forums"}
         ]
       }}
    end
  end

  defmodule FakeAuthorizedUrlBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.example.com/support/authorized-integrators",
         title: "Authorized Integrators",
         text: "Authorized integrators directory",
         headings: ["Authorized Integrators"],
         forms: [%{"action" => "/search", "method" => "get", "text" => "Search"}],
         links: [%{"href" => "https://www.example.com/support/login", "text" => "Login"}]
       }}
    end
  end

  defmodule FakeNotFoundWithHeaderLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.example.com/missing",
         title: "404 Page Not Found",
         text: "404 Page Not Found Sign in Password",
         headings: ["404 Page Not Found"],
         forms: [
           %{
             "action" => "/login",
             "method" => "post",
             "text" => "Sign in Password",
             "inputs" => [%{"type" => "password", "name" => "password"}],
             "buttons" => ["Sign in"]
           }
         ],
         links: []
       }}
    end
  end

  defmodule FakeStructuredFormValueBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://www.example.com/jobs",
         title: "Jobs",
         text: "Open jobs and careers",
         headings: ["Jobs"],
         forms: [
           %{
             "action" => "/search",
             "method" => "get",
             "text" => %{},
             "inputs" => [
               %{"type" => "text", "name" => %{}, "placeholder" => ["Search"]}
             ],
             "buttons" => [%{}]
           }
         ],
         links: [%{"href" => "https://www.example.com/jobs/open", "text" => "Open jobs"}]
       }}
    end
  end

  defmodule FakeErrorBrowser do
    def inspect_page(_url, _opts), do: {:error, "navigation failed"}
  end

  test "inspect source records a crawl run, page, snapshot artifact, and edges" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Inspectable Source",
        url: "https://example.com/source",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{run: run, page: page}} =
             Procurement.inspect_procurement_source(source, browser: FakeBrowser)

    assert run.status == :completed
    assert run.run_kind == :inspect

    assert {:ok, [loaded_run]} = Procurement.list_crawl_runs_for_source(source.id)
    assert loaded_run.summary["links"] == 2
    assert loaded_run.diagnostics["diagnosis"] == "page_inspected"

    assert {:ok, [loaded_page]} = Procurement.list_crawl_pages_for_run(run.id)
    assert loaded_page.id == page.id
    assert loaded_page.title == "Source Home"

    assert {:ok, [artifact]} = Procurement.list_page_artifacts_for_page(page.id)
    assert artifact.kind == :snapshot
    assert artifact.body =~ "Bid Opportunities"

    assert {:ok, edges} = Procurement.list_crawl_edges_for_run(run.id)
    assert length(edges) == 2
    assert Enum.any?(edges, &(&1.edge_type == :document))

    assert {:ok, candidates} = Procurement.list_extraction_candidates_for_run(run.id)
    assert length(candidates) == 2
    assert Enum.any?(candidates, &(&1.candidate_type == :bid))
    assert Enum.any?(candidates, &(&1.candidate_type == :document))
    assert Enum.all?(candidates, &(&1.status == :proposed))
    assert Enum.any?(candidates, &(&1.payload["url"] == "https://example.com/source/bids/1"))
  end

  test "inspect source marks login-gated pages as requiring credentials" do
    original_username = System.get_env("PUBLICPURCHASE_USERNAME")
    original_password = System.get_env("PUBLICPURCHASE_PASSWORD")

    System.delete_env("PUBLICPURCHASE_USERNAME")
    System.delete_env("PUBLICPURCHASE_PASSWORD")

    on_exit(fn ->
      restore_env("PUBLICPURCHASE_USERNAME", original_username)
      restore_env("PUBLICPURCHASE_PASSWORD", original_password)
    end)

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Login Source",
        url: "https://www.publicpurchase.com/gems/example/buyer/public/home",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{run: run, page: page, source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source, browser: FakeLoginBrowser)

    assert inspected_source.requires_login
    assert inspection["diagnosis"] == "login_required"
    assert "password_input" in inspection["login_evidence"]

    assert {:ok, loaded_source} = Procurement.get_procurement_source(source.id)
    assert loaded_source.requires_login
    assert loaded_source.metadata["credential_family"] == "publicpurchase"

    assert {:ok, loaded_run} = Procurement.get_crawl_run(run.id)
    assert loaded_run.diagnostics["diagnosis"] == "login_required"

    assert {:ok, loaded_page} = Procurement.get_crawl_page(page.id)
    assert loaded_page.diagnostics["diagnosis"] == "login_required"
    assert loaded_page.diagnostics["password_inputs"] == 1

    assert {:ok, acquisition_source} =
             GnomeGarden.Acquisition.get_source_by_external_ref("procurement_source:#{source.id}")

    assert {:ok, acquisition_source} =
             GnomeGarden.Acquisition.get_source(acquisition_source.id,
               load: [:health_status, :health_note, :runnable]
             )

    assert acquisition_source.health_status == :needs_login
    assert acquisition_source.health_note =~ "PublicPurchase credentials are missing"
    refute acquisition_source.runnable
  end

  test "inspect source does not mark public pages with header login forms as credential gated" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Public Header Login",
        url: "https://www.bidnetdirect.com/california/example",
        source_type: :bidnet,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source, browser: FakePublicHeaderLoginBrowser)

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_inspected"
    assert inspection["password_inputs"] == 1
    assert inspection["public_listing_links"] == 2
  end

  test "inspect source does not mark public job boards with login forms as credential gated" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Public Job Board",
        url: "https://www.example.com/jobs",
        source_type: :job_board,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source,
               browser: FakePublicJobBoardLoginBrowser
             )

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_inspected"
    assert inspection["password_inputs"] == 1
    assert inspection["public_listing_links"] == 1
  end

  test "inspect source does not mark public directories with login forms as credential gated" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Public Directory",
        url: "https://www.example.com/directory",
        source_type: :directory,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source,
               browser: FakePublicDirectoryLoginBrowser
             )

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_inspected"
    assert inspection["password_inputs"] == 1
    assert inspection["public_listing_links"] == 2
  end

  test "inspect source does not mark public forums with login forms as credential gated" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Public Forum",
        url: "https://www.example.com/forums",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source, browser: FakePublicForumLoginBrowser)

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_inspected"
    assert inspection["password_inputs"] == 1
    assert inspection["public_listing_links"] == 2
  end

  test "inspect source does not treat authorized URL paths as auth gates" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Authorized Directory",
        url: "https://www.example.com/support/authorized-integrators",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source, browser: FakeAuthorizedUrlBrowser)

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_inspected"
    refute "login_url" in inspection["login_evidence"]
  end

  test "inspect source does not treat unavailable pages with header login as credential gated" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Missing Partner Page",
        url: "https://www.example.com/missing",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source,
               browser: FakeNotFoundWithHeaderLoginBrowser
             )

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_unavailable"
    assert inspection["password_inputs"] == 1
  end

  test "inspect source ignores non-text form metadata" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Structured Form",
        url: "https://www.example.com/jobs",
        source_type: :job_board,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection}} =
             Procurement.inspect_procurement_source(source,
               browser: FakeStructuredFormValueBrowser
             )

    refute inspected_source.requires_login
    assert inspection["diagnosis"] == "page_inspected"
  end

  test "inspect source marks crawl run failed when browser inspection fails" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Broken Source",
        url: "https://broken.example.com",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:error, "navigation failed"} =
             Procurement.inspect_procurement_source(source, browser: FakeErrorBrowser)

    assert {:ok, [run]} = Procurement.list_crawl_runs_for_source(source.id)
    assert run.status == :failed
    assert run.diagnostics["diagnosis"] == "inspection_failed"
    assert run.diagnostics["reason"] == "navigation failed"
  end

  defp restore_env(_name, nil), do: :ok
  defp restore_env(name, value), do: System.put_env(name, value)
end
