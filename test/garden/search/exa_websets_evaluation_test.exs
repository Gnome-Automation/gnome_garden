defmodule GnomeGarden.Search.ExaWebsetsEvaluationTest do
  use ExUnit.Case, async: true

  @fixture_root Path.expand("../../fixtures/exa_websets/v0", __DIR__)

  defmodule SpikeClient do
    @moduledoc false

    @base_url "https://api.exa.ai/websets/v0"

    def preview(search, opts) do
      with {:ok, payload} <- post("/websets/preview", %{"search" => search}, opts) do
        {:ok,
         %{
           entity: get_in(payload, ["search", "entity", "type"]),
           criteria: get_in(payload, ["search", "criteria"]) || [],
           suggested_enrichments: payload["enrichments"] || [],
           candidates: Enum.map(payload["items"] || [], &candidate/1)
         }}
      end
    end

    def list_items(webset_id, opts) do
      with {:ok, payload} <- get("/websets/#{webset_id}/items", opts) do
        {:ok,
         %{
           candidates: Enum.map(payload["data"] || [], &candidate/1),
           has_more?: payload["hasMore"] || false,
           next_cursor: payload["nextCursor"]
         }}
      end
    end

    def create_monitor(params, opts) do
      with {:ok, payload} <- post("/monitors", params, opts) do
        {:ok,
         %{
           id: payload["id"],
           status: payload["status"],
           webset_id: payload["websetId"],
           cadence: payload["cadence"],
           behavior: payload["behavior"],
           next_run_at: payload["nextRunAt"]
         }}
      end
    end

    def normalize_event(%{
          "id" => event_id,
          "type" => "webset.item.created" = type,
          "data" => item
        }) do
      {:ok, %{event_id: event_id, type: type, candidate: candidate(item)}}
    end

    def normalize_event(_payload), do: {:error, :unsupported_websets_event}

    defp candidate(item) do
      properties = item["properties"] || %{}
      company = properties["company"] || %{}

      %{
        external_id: item["id"],
        webset_id: item["websetId"],
        source_id: item["sourceId"],
        title: company["name"],
        url: properties["url"],
        description: properties["description"],
        location: company["location"],
        evaluations: item["evaluations"] || [],
        enrichments: item["enrichments"] || []
      }
    end

    defp post(path, body, opts) do
      (@base_url <> path)
      |> Req.post(request_options(opts, json: body))
      |> response()
    end

    defp get(path, opts) do
      (@base_url <> path)
      |> Req.get(request_options(opts, []))
      |> response()
    end

    defp request_options(opts, request_opts) do
      [headers: [{"x-api-key", Keyword.fetch!(opts, :api_key)}]]
      |> Keyword.merge(Keyword.get(opts, :req_options, []))
      |> Keyword.merge(request_opts)
    end

    defp response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
      do: {:ok, body}

    defp response({:ok, %Req.Response{status: status, body: body}}),
      do: {:error, {:http_error, status, body}}

    defp response({:error, reason}), do: {:error, reason}
  end

  test "preview exposes generated criteria and candidate shape without creating provider state" do
    payload = fixture("preview-success.json")

    Req.Test.stub(SpikeClient, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/websets/v0/websets/preview"
      assert Plug.Conn.get_req_header(conn, "x-api-key") == ["fixture-key"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      assert request == %{
               "search" => %{
                 "query" => "Southern California manufacturers needing controls integration",
                 "entity" => %{"type" => "company"},
                 "count" => 10
               }
             }

      Req.Test.json(conn, payload)
    end)

    assert {:ok, preview} =
             SpikeClient.preview(
               %{
                 "query" => "Southern California manufacturers needing controls integration",
                 "entity" => %{"type" => "company"},
                 "count" => 10
               },
               client_opts()
             )

    assert preview.entity == "company"
    assert length(preview.criteria) == 2
    assert length(preview.suggested_enrichments) == 2

    assert [%{title: "Acme Manufacturing", url: "https://acme.example.com"}] =
             preview.candidates
  end

  test "item listing carries criterion reasoning, references, and enrichment provenance" do
    payload = fixture("items-success.json")

    Req.Test.stub(SpikeClient, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/websets/v0/websets/webset_garden_shadow/items"
      Req.Test.json(conn, payload)
    end)

    assert {:ok, %{candidates: [candidate], has_more?: false, next_cursor: nil}} =
             SpikeClient.list_items("webset_garden_shadow", client_opts())

    assert candidate.external_id == "item_acme"
    assert candidate.location == "Orange County, California"
    assert Enum.all?(candidate.evaluations, &(&1["satisfied"] == "yes"))
    assert Enum.all?(candidate.evaluations, &(&1["reasoning"] not in [nil, ""]))
    assert Enum.all?(candidate.evaluations, &(&1["references"] != []))

    assert [enrichment] = candidate.enrichments
    assert enrichment["result"] == ["operations@acme.example.com"]
    assert enrichment["references"] != []
  end

  test "monitor creation is externally scheduled state with a daily-or-slower cadence" do
    payload = fixture("monitor-success.json")
    params = payload |> Map.take(["websetId", "cadence", "behavior", "metadata"])

    Req.Test.stub(SpikeClient, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/websets/v0/monitors"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == params
      Req.Test.json(conn, payload)
    end)

    assert {:ok, monitor} = SpikeClient.create_monitor(params, client_opts())
    assert monitor.status == "enabled"
    assert monitor.cadence == %{"cron" => "0 9 * * 1", "timezone" => "America/Los_Angeles"}
    assert monitor.behavior["config"]["behavior"] == "append"
    assert monitor.next_run_at == "2026-07-20T16:00:00Z"
  end

  test "webhook event identity can map to a candidate but signature custody remains deferred" do
    assert {:ok, event} =
             "item-created-event.json"
             |> fixture()
             |> SpikeClient.normalize_event()

    assert event.event_id == "event_item_acme_created"
    assert event.type == "webset.item.created"
    assert event.candidate.webset_id == "webset_garden_shadow"
    assert event.candidate.url == "https://acme.example.com"
  end

  test "fixtures are synthetic, redacted, offline, and pinned to the evaluated API version" do
    provenance = fixture("provenance.json")

    assert provenance["api_version"] == "websets/v0"
    assert provenance["redacted"]
    refute provenance["live_network_required"]
    refute provenance["secrets_required"]
    assert Enum.all?(provenance["official_docs"], &String.starts_with?(&1, "https://exa.ai/"))
  end

  defp client_opts do
    [api_key: "fixture-key", req_options: [plug: {Req.Test, SpikeClient}]]
  end

  defp fixture(name) do
    @fixture_root
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
