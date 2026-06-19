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
end
