defmodule GnomeGarden.Procurement.SourcePipelineTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourcePipeline

  defmodule FakeLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://secure.example.com/login",
         title: "Vendor Login",
         text: "Please sign in to continue.",
         headings: ["Vendor Login"],
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
         links: []
       }}
    end
  end

  defmodule FakeScanner do
    def scan(source, context) do
      {:ok,
       %{
         extracted: 2,
         excluded: 1,
         scored: 1,
         saved: 1,
         source_id: source.id,
         context_marker: context[:marker]
       }}
    end
  end

  test "inspection runs through the Lua source pipeline and preserves inspection result" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Credential Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, inspection: inspection, pipeline: pipeline}} =
             SourcePipeline.inspect_source(source, browser: FakeLoginBrowser)

    assert inspected_source.requires_login
    assert inspection["diagnosis"] == "login_required"
    assert pipeline["mode"] == "credentials_needed"
    assert pipeline["requires_login"]
  end

  test "auto configuration stops at credentials needed before launching discovery" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Credential Discovery Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, %{source: inspected_source, mode: :credentials_needed, pipeline: pipeline}} =
             SourcePipeline.auto_configure_source(source,
               browser: FakeLoginBrowser,
               async?: false
             )

    assert inspected_source.requires_login
    assert pipeline["mode"] == "credentials_needed"
    assert pipeline["diagnosis"] == "login_required"
  end

  test "source scans run through the Lua source pipeline" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Ready Scanner Source",
        url: "https://example.com/bids",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    assert {:ok, result} =
             SourcePipeline.scan_source(source,
               scanner: FakeScanner,
               scanner_context: %{marker: "lua-scan"}
             )

    assert result.saved == 1
    assert result.context_marker == "lua-scan"
    assert result.pipeline["mode"] == "scanned"
    assert result.pipeline["saved"] == 1
  end

  test "AshLua transactions roll back procurement source writes" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Transactional Lua Source",
        url: "https://example.com/transactional",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    script = """
    local _, err = utils.transaction.transact({ "procurement.procurement_source" }, function()
      assert(procurement.procurement_source.update({
        id = "#{source.id}",
        requires_login = true
      }))

      utils.transaction.rollback("rollback test")
    end)

    return err
    """

    {[error], _lua} = AshLua.eval!(script, otp_app: :gnome_garden)
    error = normalize_lua_value(error)

    assert %{"errors" => [%{"message" => "rollback test"} | _]} = error
    assert {:ok, reloaded} = Procurement.get_procurement_source(source.id)
    refute reloaded.requires_login
  end

  defp normalize_lua_value(value) when is_list(value) do
    cond do
      Enum.all?(value, &match?({key, _value} when is_binary(key), &1)) ->
        Map.new(value, fn {key, nested_value} -> {key, normalize_lua_value(nested_value)} end)

      Enum.all?(value, &match?({key, _value} when is_integer(key), &1)) ->
        value
        |> Enum.sort_by(fn {key, _value} -> key end)
        |> Enum.map(fn {_key, nested_value} -> normalize_lua_value(nested_value) end)

      true ->
        Enum.map(value, &normalize_lua_value/1)
    end
  end

  defp normalize_lua_value(value), do: value
end
