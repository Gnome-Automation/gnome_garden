defmodule GnomeGarden.Search.ExaTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Search.Exa

  test "normalizes a successful search response and surfaces cost" do
    Req.Test.stub(Exa, fn conn ->
      Req.Test.json(conn, %{
        "costDollars" => %{"total" => 0.007, "search" => %{"neural" => 0.007}},
        "resolvedSearchType" => "neural",
        "results" => [
          %{"title" => "Acme Manufacturing", "url" => "https://acme.example.com", "publishedDate" => "2026-05-01T00:00:00.000Z"},
          %{"title" => nil, "url" => "https://no-title.example.com"}
        ]
      })
    end)

    assert {:ok, %{cost: 0.007, resolved_type: "neural", results: results}} =
             Exa.search("manufacturers expanding production southern california")

    assert [first, second] = results
    assert first.title == "Acme Manufacturing"
    assert first.url == "https://acme.example.com"
    assert first.published_date == "2026-05-01T00:00:00.000Z"
    assert second.title == nil
    assert second.url == "https://no-title.example.com"
  end

  test "sends the query, num_results, type and category in the request body" do
    Req.Test.stub(Exa, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["query"] == "food processing plant hiring"
      assert decoded["numResults"] == 5
      assert decoded["type"] == "neural"
      assert decoded["category"] == "company"

      Req.Test.json(conn, %{"costDollars" => %{"total" => 0.005}, "results" => []})
    end)

    assert {:ok, %{results: []}} =
             Exa.search("food processing plant hiring", num_results: 5, type: "neural", category: "company")
  end

  test "returns an error tuple on a non-200 response" do
    Req.Test.stub(Exa, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => "rate limited"})
    end)

    assert {:error, {:http_error, 429, _body}} = Exa.search("anything")
  end

  describe "contents/2" do
    test "sends urls, subpages, targets and a summary schema; parses the summary JSON" do
      test_pid = self()

      Req.Test.stub(Exa, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:contents_body, Jason.decode!(body)})

        Req.Test.json(conn, %{
          "costDollars" => %{"total" => 0.006},
          "results" => [
            %{
              "url" => "https://acme.example.com",
              "title" => "Acme",
              "text" => "Call us at 714-555-1212",
              "summary" => ~s({"people":[{"name":"Jane Doe","title":"VP Ops"}],"firmographic":{"summary":"A maker."}}),
              "subpages" => [
                %{"url" => "https://acme.example.com/contact", "title" => "Contact", "text" => "info@acme.example.com"}
              ]
            }
          ]
        })
      end)

      assert {:ok, %{cost: 0.006, results: [result]}} =
               Exa.contents("https://acme.example.com",
                 subpages: 4,
                 subpage_target: ["contact", "about"],
                 summary_schema: %{"type" => "object"},
                 summary_query: "find people"
               )

      assert_received {:contents_body, body}
      assert body["urls"] == ["https://acme.example.com"]
      assert body["subpages"] == 4
      assert body["subpageTarget"] == ["contact", "about"]
      assert body["summary"]["schema"] == %{"type" => "object"}
      assert body["summary"]["query"] == "find people"

      # Summary string parsed into a map; subpages normalized recursively.
      assert result.summary["people"] == [%{"name" => "Jane Doe", "title" => "VP Ops"}]
      assert [subpage] = result.subpages
      assert subpage.url == "https://acme.example.com/contact"
      assert subpage.text == "info@acme.example.com"
    end

    test "omits text when max_characters is false" do
      test_pid = self()

      Req.Test.stub(Exa, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:contents_body, Jason.decode!(body)})
        Req.Test.json(conn, %{"costDollars" => %{"total" => 0.001}, "results" => []})
      end)

      assert {:ok, %{results: []}} = Exa.contents("https://acme.example.com", max_characters: false)

      assert_received {:contents_body, body}
      refute Map.has_key?(body, "text")
    end
  end
end
