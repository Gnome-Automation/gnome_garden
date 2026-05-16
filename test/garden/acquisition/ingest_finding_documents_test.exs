defmodule GnomeGarden.Acquisition.IngestFindingDocumentsTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.Workers.IngestFindingDocuments
  alias GnomeGarden.Procurement

  setup do
    previous = Application.get_env(:gnome_garden, :acquisition_document_downloader)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:gnome_garden, :acquisition_document_downloader)
      else
        Application.put_env(:gnome_garden, :acquisition_document_downloader, previous)
      end
    end)

    :ok
  end

  test "ingests bid packet descriptors through the configured downloader" do
    Application.put_env(
      :gnome_garden,
      :acquisition_document_downloader,
      __MODULE__.SuccessfulDownloader
    )

    {:ok, bid} = create_bid_with_documents("INGEST-PACKET-SUCCESS")
    {:ok, finding} = Acquisition.get_finding_by_source_bid(bid.id)

    assert :ok = IngestFindingDocuments.perform(%Oban.Job{args: %{"bid_id" => bid.id}})

    assert {:ok, [finding_document]} =
             Acquisition.list_finding_documents_for_finding(finding.id)

    assert finding_document.document_role == :solicitation
    assert finding_document.metadata["source_url"] =~ "planetbids.test"
    assert finding_document.document.title == "packet.txt"
    assert finding_document.document.document_type == :solicitation

    assert {:ok, refreshed_bid} = Procurement.get_bid(bid.id)
    assert refreshed_bid.metadata["packet"]["status"] == "present"
    assert refreshed_bid.metadata["packet"]["document_count"] == 1
    assert refreshed_bid.metadata["packet"]["failed_count"] == 0
  end

  test "records login-required packet state when protected documents cannot be downloaded" do
    Application.put_env(
      :gnome_garden,
      :acquisition_document_downloader,
      __MODULE__.LoginRequiredDownloader
    )

    {:ok, bid} = create_bid_with_documents("INGEST-PACKET-LOGIN")

    assert :ok = IngestFindingDocuments.perform(%Oban.Job{args: %{"bid_id" => bid.id}})

    assert {:ok, finding} = Acquisition.get_finding_by_source_bid(bid.id)
    assert {:ok, []} = Acquisition.list_finding_documents_for_finding(finding.id)

    assert {:ok, refreshed_bid} = Procurement.get_bid(bid.id)
    assert refreshed_bid.metadata["packet"]["status"] == "login_required"
    assert refreshed_bid.metadata["packet"]["document_count"] == 0
    assert refreshed_bid.metadata["packet"]["failed_count"] == 1
    assert [%{"reason" => reason}] = refreshed_bid.metadata["packet"]["errors"]
    assert reason =~ "login_required"
  end

  defmodule SuccessfulDownloader do
    def download(_descriptor) do
      path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}-packet.txt")
      File.write!(path, "SCADA PLC controls scope packet")
      {:ok, path, "text/plain"}
    end
  end

  defmodule LoginRequiredDownloader do
    def download(_descriptor), do: {:error, :login_required}
  end

  defp create_bid_with_documents(external_id) do
    Procurement.create_bid(%{
      title: "Credentialed Packet Retrofit #{external_id}",
      url: "https://vendors.planetbids.test/portal/bid/#{external_id}",
      external_id: external_id,
      description: "Controls retrofit with a protected solicitation packet.",
      agency: "Regional Utility",
      location: "Anaheim, CA",
      due_at: ~U[2026-05-24 17:00:00Z],
      region: :oc,
      score_total: 86,
      score_tier: :hot,
      metadata: %{
        "documents" => [
          %{
            "url" => "https://vendors.planetbids.test/portal/documents/#{external_id}/packet.txt",
            "filename" => "packet.txt",
            "document_type" => "solicitation",
            "requires_login" => true,
            "captured_from" => "https://vendors.planetbids.test/portal/bid/#{external_id}"
          }
        ]
      }
    })
  end
end
