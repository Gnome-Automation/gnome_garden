defmodule GnomeGardenWeb.PiDocumentControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  test "requires pi service auth", %{conn: conn} do
    conn = get(conn, ~p"/api/pi/documents/#{Ecto.UUID.generate()}")

    assert json_response(conn, 401) == %{"success" => false, "error" => "unauthorized"}
  end

  test "lists finding documents through the app boundary", %{conn: conn} do
    {:ok, finding, document} = finding_with_document_fixture()

    conn =
      conn
      |> pi_auth()
      |> get(~p"/api/pi/findings/#{finding.id}/documents")

    assert %{
             "success" => true,
             "data" => %{
               "documents" => [
                 %{
                   "document_role" => "solicitation",
                   "document" => payload
                 }
               ]
             }
           } = json_response(conn, 200)

    assert payload["id"] == document.id
    assert payload["title"] == "Pi Procurement Packet"
    assert payload["download_url"] =~ "/api/pi/documents/#{document.id}/download"
    refute Map.has_key?(payload, "storage_key")
    refute Map.has_key?(payload["file"], "storage_key")
  end

  test "shows document metadata and streams document bytes through the app", %{conn: conn} do
    {:ok, _finding, document} = finding_with_document_fixture()

    show_conn =
      conn
      |> pi_auth()
      |> get(~p"/api/pi/documents/#{document.id}")

    assert %{
             "success" => true,
             "data" => %{
               "document" => %{
                 "id" => document_id,
                 "file" => %{
                   "filename" => "pi-procurement-packet.pdf",
                   "content_type" => "application/pdf",
                   "byte_size" => 21
                 }
               }
             }
           } = json_response(show_conn, 200)

    assert document_id == document.id

    download_conn =
      conn
      |> pi_auth()
      |> get(~p"/api/pi/documents/#{document.id}/download")

    assert response(download_conn, 200) == "pi procurement packet"
    assert get_resp_header(download_conn, "content-type") == ["application/pdf; charset=utf-8"]
    assert [content_disposition] = get_resp_header(download_conn, "content-disposition")
    assert content_disposition =~ ~s[filename="pi-procurement-packet.pdf"]
  end

  defp pi_auth(conn) do
    put_req_header(conn, "authorization", "Bearer dev-pi-token")
  end

  defp finding_with_document_fixture do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Pi Document Retrofit",
        url: "https://example.com/bids/pi-document-retrofit",
        external_id: "PI-DOCUMENT-RETROFIT",
        description: "Controls retrofit with a packet for Pi retrieval.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-24 17:00:00Z],
        region: :oc,
        score_total: 86,
        score_tier: :hot,
        score_recommendation: "Review packet"
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    upload = %Plug.Upload{
      path: write_temp_packet!("pi-procurement-packet.pdf", "pi procurement packet"),
      filename: "pi-procurement-packet.pdf",
      content_type: "application/pdf"
    }

    {:ok, document} =
      Acquisition.upload_document_for_finding(%{
        title: "Pi Procurement Packet",
        summary: "Packet available through the app boundary.",
        document_type: :solicitation,
        source_url: finding.source_url,
        file: upload,
        finding_id: finding.id,
        document_role: :solicitation,
        notes: "Available for Pi retrieval."
      })

    {:ok, finding, document}
  end

  defp write_temp_packet!(filename, contents) do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
