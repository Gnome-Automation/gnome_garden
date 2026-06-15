defmodule GnomeGardenWeb.CompanyAreaLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration

  setup do
    AshStorage.Service.Test.reset!()
    :ok
  end

  test "company documents page uploads a reusable company document", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/company/documents")

    assert html =~ "Documents"
    assert html =~ "Search documents"
    assert html =~ "Upload Document"

    view
    |> element("#open-company-document-upload")
    |> render_click()

    assert render(view) =~ "Drop a file here"

    contents = "irs confirmation placeholder"

    upload =
      file_input(view, "#company-document-form", :file, [
        %{
          name: "cp-575.pdf",
          content: contents,
          size: byte_size(contents),
          type: "application/pdf"
        }
      ])

    assert render_upload(upload, "cp-575.pdf") =~ "100%"

    view
    |> form("#company-document-form", %{
      "document" => %{
        "title" => "CP 575",
        "key" => "cp-575",
        "kind" => "tax_certificate",
        "status" => "active",
        "description" => "IRS EIN assignment letter.",
        "tags" => "tax, vendor setup, Tax"
      }
    })
    |> render_submit()

    assert render(view) =~ "CP 575"
    assert render(view) =~ "Tax identity"
    assert render(view) =~ "vendor setup"

    profile = DefaultRegistration.ensure_default().profile
    assert {:ok, [document]} = Company.list_company_documents_for_profile(profile.id)
    assert document.title == "CP 575"
    assert document.kind == :tax_certificate
    assert document.metadata["tags"] == ["tax", "vendor setup"]

    view
    |> element("button", "Edit")
    |> render_click()

    assert render(view) =~ "Edit Company Document"

    view
    |> form("#company-document-edit-form", %{
      "document" => %{
        "title" => "CP 575 EIN letter",
        "key" => "cp-575",
        "kind" => "tax_certificate",
        "status" => "active",
        "description" => "IRS EIN assignment letter for vendor setup.",
        "tags" => "ein, customer portal"
      }
    })
    |> render_submit()

    assert render(view) =~ "CP 575 EIN letter"
    assert render(view) =~ "customer portal"

    assert {:ok, [updated]} = Company.list_company_documents_for_profile(profile.id)
    assert updated.title == "CP 575 EIN letter"
    assert updated.description == "IRS EIN assignment letter for vendor setup."
    assert updated.metadata["tags"] == ["ein", "customer portal"]
  end

  test "company compliance page shows seeded obligations and accepts new ones", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/company/compliance")

    assert html =~ "BOI report"
    assert html =~ "Registered agent renewal"

    view
    |> form("#company-compliance-form", %{
      "obligation" => %{
        "title" => "Insurance renewal review",
        "key" => "insurance-renewal-review",
        "category" => "other",
        "status" => "needs_review",
        "summary" => "Confirm whether customer portals need updated COI."
      }
    })
    |> render_submit()

    assert render(view) =~ "Insurance renewal review"
  end

  test "company sources page shows review decisions and supports status actions", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/company/sources")

    assert html =~ "Relayfi banking conflict"
    assert html =~ "CP 575 document"

    view
    |> element("#source-review-item-company-profile-boilerplate button[phx-click='ignore']")
    |> render_click()

    assert render(view) =~ "Ignored"
  end
end
