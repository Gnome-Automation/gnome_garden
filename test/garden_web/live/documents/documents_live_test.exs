defmodule GnomeGardenWeb.Documents.DocumentsLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Documents

  setup :register_and_log_in_user

  defp create_w9 do
    {:ok, doc} =
      Documents.create_document(%{
        name: "W9 Form",
        category: :tax,
        version: "2024",
        file_path: "documents/w9-gnome-automation-signed.pdf",
        status: :active
      })
    doc
  end

  test "renders documents page", %{conn: conn} do
    create_w9()
    {:ok, _view, html} = live(conn, ~p"/operations/documents")
    assert html =~ "Company Documents"
    assert html =~ "W9 Form"
  end

  test "search filters documents by name", %{conn: conn} do
    create_w9()

    {:ok, _} =
      Documents.create_document(%{
        name: "NDA Agreement",
        category: :legal,
        version: "1.0",
        file_path: "documents/nda.pdf",
        status: :active
      })

    {:ok, view, _html} = live(conn, ~p"/operations/documents")

    html = render_keyup(view, "search", %{"value" => "W9"})
    assert html =~ "W9 Form"
    refute html =~ "NDA Agreement"
  end

  test "send modal opens when send button clicked", %{conn: conn} do
    create_w9()
    {:ok, view, _html} = live(conn, ~p"/operations/documents")

    html = view |> element("[phx-click='open_send_modal']") |> render_click()
    assert html =~ "Send Document"
    assert html =~ "To"
  end

  test "send document creates send log", %{conn: conn, current_user: user} do
    doc = create_w9()
    {:ok, view, _html} = live(conn, ~p"/operations/documents")

    view |> element("[phx-click='open_send_modal'][phx-value-doc-id='#{doc.id}']") |> render_click()

    view
    |> form("#send-document-form",
        send_doc: %{
          to: "client@example.com",
          subject: "Gnome Automation — W9 Form",
          message: ""
        }
      )
    |> render_submit()

    {:ok, logs} = Documents.list_send_logs_for_document(doc.id)
    assert Enum.any?(logs, &(&1.sent_to_email == "client@example.com"))
  end

  test "send log section shows recent sends", %{conn: conn, current_user: user} do
    doc = create_w9()

    {:ok, _} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "previous@example.com",
        sent_by_user_id: user.id
      })

    {:ok, view, _html} = live(conn, ~p"/operations/documents")
    html = view |> element("[phx-click='toggle_send_log']") |> render_click()
    assert html =~ "previous@example.com"
  end
end
