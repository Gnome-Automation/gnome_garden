defmodule GnomeGardenWeb.AcquisitionFindingDocumentLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  test "uploading a procurement document links it to the finding and clears promotion blockers",
       %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Upload Packet Retrofit",
        url: "https://example.com/bids/upload-packet-retrofit",
        external_id: "UPLOAD-PACKET-RETROFIT",
        description: "Controls retrofit with a real due date and clear scope.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-24 17:00:00Z],
        region: :oc,
        score_total: 86,
        score_tier: :hot,
        score_recommendation: "Promote after packet upload"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified controls retrofit with concrete deadline and fit."
             })

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}/documents/new")

    packet = "procurement packet"

    upload =
      file_input(view, "#finding-document-form", :file, [
        %{
          name: "procurement-packet.pdf",
          content: packet,
          size: byte_size(packet),
          type: "application/pdf"
        }
      ])

    assert render_upload(upload, "procurement-packet.pdf") =~ "100%"

    submit_result =
      view
      |> form("#finding-document-form", %{
        "form" => %{
          "title" => "Procurement Packet",
          "document_type" => "solicitation",
          "source_url" => bid.url,
          "summary" => "Downloaded packet captured during intake review."
        },
        "finding_document" => %{
          "document_role" => "solicitation",
          "notes" => "Required before commercial handoff."
        }
      })
      |> render_submit()

    assert {:error, {:live_redirect, %{to: path}}} = submit_result
    assert path == ~p"/acquisition/findings/#{finding.id}"

    {:ok, show_view, _html} = live(conn, path)

    assert render(show_view) =~ "Linked Documents"
    assert render(show_view) =~ "Procurement Packet"
    assert render(show_view) =~ "Required before commercial handoff."
    assert render(show_view) =~ "Counts for promotion"

    {:ok, refreshed_finding} =
      Acquisition.get_finding(
        finding.id,
        load: [:document_count, :promotion_document_count, :promotion_ready, :promotion_blockers]
      )

    assert refreshed_finding.document_count == 1
    assert refreshed_finding.promotion_document_count == 1
    assert refreshed_finding.promotion_ready
    assert refreshed_finding.promotion_blockers == []
  end

  test "linked procurement documents can be removed from the finding detail", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Remove Packet Retrofit",
        url: "https://example.com/bids/remove-packet-retrofit",
        external_id: "REMOVE-PACKET-RETROFIT",
        description: "Controls retrofit with a packet that may need to be relinked.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-25 17:00:00Z],
        region: :oc,
        score_total: 82,
        score_tier: :hot,
        score_recommendation: "Packet linked for handoff"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified controls retrofit ready for packet review."
             })

    assert {:ok, _document} = create_linked_document!(finding)

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}")

    assert render(view) =~ "Linked Documents"
    assert render(view) =~ "Procurement Packet"

    {:ok, [finding_document | _rest]} =
      Acquisition.list_finding_documents_for_finding(finding.id)

    view
    |> element("#finding-document-remove-#{finding_document.id}")
    |> render_click()

    assert render(view) =~ "No documents linked yet."

    {:ok, refreshed_finding} =
      Acquisition.get_finding(
        finding.id,
        load: [:document_count, :promotion_document_count, :promotion_ready, :promotion_blockers]
      )

    assert refreshed_finding.document_count == 0
    assert refreshed_finding.promotion_document_count == 0
    refute refreshed_finding.promotion_ready

    assert refreshed_finding.promotion_blockers == [
             "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."
           ]
  end

  test "existing acquisition documents can be linked into a finding without re-uploading",
       %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Link Existing Packet Retrofit",
        url: "https://example.com/bids/link-existing-packet-retrofit",
        external_id: "LINK-EXISTING-PACKET-RETROFIT",
        description: "Controls retrofit that can reuse a previously captured packet.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-26 17:00:00Z],
        region: :oc,
        score_total: 85,
        score_tier: :hot,
        score_recommendation: "Link an existing packet"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified controls retrofit ready to reuse an existing packet."
             })

    assert {:ok, existing_document} = create_unlinked_document!()

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}/documents/new")

    assert render(view) =~ "Shared Procurement Packet"

    submit_result =
      view
      |> form("#finding-document-link-form", %{
        "link" => %{
          "document_id" => existing_document.id,
          "document_role" => "solicitation",
          "notes" => "Linked from the shared document library."
        }
      })
      |> render_submit()

    assert {:error, {:live_redirect, %{to: path}}} = submit_result
    assert path == ~p"/acquisition/findings/#{finding.id}"

    {:ok, show_view, _html} = live(conn, path)

    assert render(show_view) =~ "Shared Procurement Packet"
    assert render(show_view) =~ "Linked from the shared document library."
    assert render(show_view) =~ "Counts for promotion"

    {:ok, refreshed_finding} =
      Acquisition.get_finding(
        finding.id,
        load: [:document_count, :promotion_document_count, :promotion_ready, :promotion_blockers]
      )

    assert refreshed_finding.document_count == 1
    assert refreshed_finding.promotion_document_count == 1
    assert refreshed_finding.promotion_ready
    assert refreshed_finding.promotion_blockers == []
  end

  test "uploading only an intake note keeps procurement promotion blocked", %{conn: conn} do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Upload Intake Note Retrofit",
        url: "https://example.com/bids/upload-intake-note-retrofit",
        external_id: "UPLOAD-INTAKE-NOTE-RETROFIT",
        description: "Procurement finding that still needs a substantive packet.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-27 17:00:00Z],
        region: :oc,
        score_total: 78,
        score_tier: :hot,
        score_recommendation: "Needs a real packet"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")
    assert {:ok, _finding} = Acquisition.start_review_for_finding(finding.id)

    assert {:ok, _finding} =
             Acquisition.accept_finding_review(finding.id, %{
               reason: "Qualified, but only an intake note is available so far."
             })

    {:ok, view, _html} = live(conn, ~p"/acquisition/findings/#{finding.id}/documents/new")

    note = "procurement intake note"

    upload =
      file_input(view, "#finding-document-form", :file, [
        %{
          name: "procurement-intake-note.txt",
          content: note,
          size: byte_size(note),
          type: "text/plain"
        }
      ])

    assert render_upload(upload, "procurement-intake-note.txt") =~ "100%"

    submit_result =
      view
      |> form("#finding-document-form", %{
        "form" => %{
          "title" => "Procurement Intake Note",
          "document_type" => "intake_note",
          "source_url" => bid.url,
          "summary" => "Operator note captured before the real packet was downloaded."
        },
        "finding_document" => %{
          "document_role" => "supporting",
          "notes" => "Should not clear promotion readiness."
        }
      })
      |> render_submit()

    assert {:error, {:live_redirect, %{to: path}}} = submit_result

    {:ok, show_view, _html} = live(conn, path)

    assert render(show_view) =~
             "Attach a substantive procurement packet (solicitation, scope, pricing, or addendum) before promotion."

    assert render(show_view) =~ "Reference only"

    {:ok, refreshed_finding} =
      Acquisition.get_finding(
        finding.id,
        load: [:document_count, :promotion_document_count, :promotion_ready, :promotion_blockers]
      )

    assert refreshed_finding.document_count == 1
    assert refreshed_finding.promotion_document_count == 0
    refute refreshed_finding.promotion_ready
  end

  defp create_linked_document!(finding) do
    upload = %Plug.Upload{
      path: write_temp_packet!("existing-procurement-packet.pdf", "existing procurement packet"),
      filename: "existing-procurement-packet.pdf",
      content_type: "application/pdf"
    }

    Acquisition.create_document(%{
      title: "Procurement Packet",
      summary: "Linked procurement packet captured during intake review.",
      document_type: :solicitation,
      source_url: finding.source_url,
      file: upload,
      finding_documents: [
        %{
          finding_id: finding.id,
          document_role: :solicitation,
          notes: "Required before commercial handoff."
        }
      ]
    })
  end

  defp create_unlinked_document! do
    upload = %Plug.Upload{
      path: write_temp_packet!("shared-procurement-packet.pdf", "shared procurement packet"),
      filename: "shared-procurement-packet.pdf",
      content_type: "application/pdf"
    }

    Acquisition.create_document(%{
      title: "Shared Procurement Packet",
      summary: "Reusable packet captured earlier in acquisition review.",
      document_type: :solicitation,
      source_url: "https://example.com/shared-procurement-packet",
      file: upload
    })
  end

  defp write_temp_packet!(filename, contents) do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
