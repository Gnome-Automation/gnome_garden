defmodule GnomeGarden.Acquisition.DocumentAnalysisTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Procurement

  test "uploaded documents are analyzed through AshStorage analyzers" do
    {:ok, bid} =
      Procurement.create_bid(%{
        title: "Analyzed Packet Retrofit",
        url: "https://example.com/bids/analyzed-packet-retrofit",
        external_id: "ANALYZED-PACKET-RETROFIT",
        description: "SCADA and PLC controls packet.",
        agency: "Regional Utility",
        location: "Anaheim, CA",
        due_at: ~U[2026-05-24 17:00:00Z],
        region: :oc,
        score_total: 86,
        score_tier: :hot
      })

    {:ok, finding} = Acquisition.get_finding_by_external_ref("procurement_bid:#{bid.id}")

    upload = %Plug.Upload{
      path:
        write_temp_packet!("analysis-packet.txt", "SCADA PLC controls scope for water telemetry."),
      filename: "analysis-packet.txt",
      content_type: "text/plain"
    }

    assert {:ok, document} =
             Acquisition.upload_document_for_finding(%{
               title: "Analysis Packet",
               document_type: :solicitation,
               source_url: finding.source_url,
               file: upload,
               finding_id: finding.id,
               document_role: :solicitation
             })

    assert {:ok, loaded} = Acquisition.get_document(document.id, load: [file: :blob])

    analysis = loaded.file.blob.metadata["document_analysis"]
    assert analysis["status"] == "complete"
    assert analysis["tool"] == "file"
    assert analysis["text_excerpt"] =~ "SCADA PLC controls"
    assert "scada" in analysis["keyword_hits"]
    assert "plc" in analysis["keyword_hits"]
  end

  defp write_temp_packet!(filename, contents) do
    path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
