defmodule GnomeGarden.Procurement.SourcePipeline do
  @moduledoc """
  Lua-backed orchestration for procurement source inspection and configuration.

  Browser execution and persistence remain in Ash/Elixir actions. Lua owns the
  source workflow decision: inspect, stop for credentials, configure a known
  provider, or queue browser discovery.
  """

  alias GnomeGarden.Agents.Procurement.SourceAutoConfigurator
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.SourceInspector
  alias GnomeGarden.Agents.Procurement.ScannerRouter

  @inspect_script """
  local inspection = source.inspect(source_context.id)

  if not inspection.ok then
    return inspection
  end

  if inspection.requires_login then
    inspection.mode = "credentials_needed"
  elseif inspection.diagnosis == "page_unavailable" then
    inspection.mode = "page_unavailable"
  else
    inspection.mode = "inspected"
  end

  return inspection
  """

  @auto_configure_script """
  if source_context.config_status == "configured" then
    return {
      ok = true,
      mode = "already_configured",
      source_id = source_context.id
    }
  end

  if source_context.config_status == "pending" then
    return {
      ok = true,
      mode = "already_pending",
      source_id = source_context.id
    }
  end

  if source_context.source_type == "planetbids" or source_context.source_type == "bidnet" then
    return source.configure(source_context.id)
  end

  local inspection = source.inspect(source_context.id)

  if not inspection.ok then
    inspection.mode = "inspection_failed"
    return inspection
  end

  if inspection.requires_login then
    inspection.mode = "credentials_needed"
    return inspection
  end

  if inspection.candidate_links and inspection.candidate_links > 0 then
    local configured = source.configure_from_inspection(source_context.id, inspection.run_id)
    configured.inspection_mode = inspection.mode
    configured.inspection_run_id = inspection.run_id

    return configured
  end

  local configured = source.configure(source_context.id)
  configured.inspection_mode = inspection.mode
  configured.inspection_run_id = inspection.run_id

  return configured
  """

  @type pipeline_result :: {:ok, map()} | {:error, term()}

  @spec inspect_source(ProcurementSource.t() | Ecto.UUID.t(), keyword()) :: pipeline_result
  def inspect_source(source_or_id, opts \\ []) do
    with {:ok, source} <- fetch_source(source_or_id, Keyword.get(opts, :actor)),
         {:ok, script_result, messages} <- run_lua(source, @inspect_script, opts),
         {:ok, inspection_result} <- source_message(messages, :inspection) do
      if truthy?(script_result["ok"]) do
        {:ok, Map.put(inspection_result, :pipeline, script_result)}
      else
        {:error, script_result["error"] || "Source inspection pipeline failed."}
      end
    end
  end

  @spec inspect_source_with_workflow(
          ProcurementSource.t() | Ecto.UUID.t(),
          GnomeGarden.Agents.AgentWorkflowDefinition.t(),
          keyword()
        ) :: pipeline_result
  def inspect_source_with_workflow(source_or_id, workflow_definition, opts \\ []) do
    with {:ok, source} <- fetch_source(source_or_id, Keyword.get(opts, :actor)),
         {:ok, script_result, messages} <- run_lua(source, workflow_definition.lua_source, opts),
         {:ok, inspection_result} <- source_message(messages, :inspection) do
      if truthy?(script_result["ok"]) do
        {:ok, Map.put(inspection_result, :pipeline, script_result)}
      else
        {:error, script_result["error"] || "Source inspection workflow failed."}
      end
    end
  end

  @spec auto_configure_source(ProcurementSource.t() | Ecto.UUID.t(), keyword()) :: pipeline_result
  def auto_configure_source(source_or_id, opts \\ []) do
    with {:ok, source} <- fetch_source(source_or_id, Keyword.get(opts, :actor)),
         {:ok, script_result, messages} <- run_lua(source, @auto_configure_script, opts) do
      mode = mode_atom(script_result["mode"])

      cond do
        not truthy?(script_result["ok"]) ->
          {:error, script_result["error"] || "Source configuration pipeline failed."}

        mode == :credentials_needed ->
          with {:ok, inspection_result} <- source_message(messages, :inspection) do
            {:ok,
             %{
               source: inspection_result.source,
               mode: :credentials_needed,
               inspection: inspection_result,
               pipeline: script_result
             }}
          end

        mode in [:already_configured, :already_pending] ->
          {:ok, %{source: source, mode: mode, pipeline: script_result}}

        true ->
          with {:ok, configuration_result} <- source_message(messages, :configuration) do
            {:ok, Map.put(configuration_result, :pipeline, script_result)}
          end
      end
    end
  end

  @spec scan_source(ProcurementSource.t() | Ecto.UUID.t(), keyword()) :: pipeline_result
  def scan_source(source_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    scanner = Keyword.get(opts, :scanner, ScannerRouter)
    scanner_context = Keyword.get(opts, :scanner_context, %{actor: actor})

    with {:ok, source} <- fetch_source(source_or_id, actor),
         :ok <- ensure_scannable(source),
         {:ok, scan_result} <- scanner.scan(source, scanner_context) do
      {:ok, put_pipeline(scan_result, scan_pipeline(scan_result))}
    end
  end

  defp ensure_scannable(%ProcurementSource{requires_login: true}),
    do: {:error, :credentials_needed}

  defp ensure_scannable(%ProcurementSource{}), do: :ok

  defp scan_pipeline(result) do
    %{
      "ok" => true,
      "mode" => "scanned",
      "extracted" => map_value(result, :extracted, 0),
      "excluded" => map_value(result, :excluded, 0),
      "scored" => map_value(result, :scored, 0),
      "saved" => map_value(result, :saved, 0),
      "enriched" => map_value(result, :enriched, 0)
    }
  end

  defp map_value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp run_lua(source, script, opts) do
    actor = Keyword.get(opts, :actor)
    async? = Keyword.get(opts, :async?, true)
    ref = make_ref()
    caller = self()

    lua =
      Lua.new()
      |> Lua.set!([:source_context], source_context(source))
      |> Lua.set!([:source, :inspect], inspect_function(ref, caller, source, opts))
      |> Lua.set!([:source, :configure], configure_function(ref, caller, actor, async?))
      |> Lua.set!(
        [:source, :configure_from_inspection],
        configure_from_inspection_function(ref, caller, actor)
      )
      |> then(
        &AshLua.new(otp_app: :gnome_garden, actor: actor, context: lua_context(opts), lua: &1)
      )

    try do
      {[raw_result], _lua} = Lua.eval!(lua, script)
      {:ok, normalize_lua_value(raw_result), collect_messages(ref, [])}
    rescue
      error in [Lua.CompilerException, Lua.RuntimeException] ->
        {:error, Exception.message(error)}
    end
  end

  defp lua_context(opts) do
    case Keyword.get(opts, :context, %{}) do
      context when is_map(context) -> context
      _other -> %{}
    end
    |> Map.put(:source_pipeline?, true)
  end

  defp inspect_function(ref, caller, source, opts) do
    fn [_source_id], lua ->
      result =
        SourceInspector.inspect_source(
          source,
          opts
          |> Keyword.delete(:async?)
          |> Keyword.delete(:pipeline?)
        )

      send(caller, {ref, :inspection, result})
      encode_lua_result(lua, serialize_inspection_result(result))
    end
  end

  defp configure_function(ref, caller, actor, async?) do
    fn [source_id], lua ->
      result =
        SourceAutoConfigurator.configure_source(source_id,
          actor: actor,
          async?: async?
        )

      send(caller, {ref, :configuration, result})
      encode_lua_result(lua, serialize_configuration_result(result))
    end
  end

  defp configure_from_inspection_function(ref, caller, actor) do
    fn [source_id, crawl_run_id], lua ->
      result = configure_candidate_link_source(source_id, crawl_run_id, actor)

      send(caller, {ref, :configuration, result})
      encode_lua_result(lua, serialize_configuration_result(result))
    end
  end

  defp configure_candidate_link_source(source_id, crawl_run_id, actor) do
    with {:ok, source} <- Procurement.get_procurement_source(source_id, actor: actor),
         {:ok, candidates} <-
           Procurement.list_extraction_candidates_for_run(crawl_run_id, actor: actor),
         bid_count when bid_count > 0 <- candidate_bid_count(candidates),
         {:ok, configured_source} <-
           Procurement.configure_procurement_source(
             source,
             %{
               scrape_config: %{
                 strategy: "candidate_links",
                 listing_url: source.url,
                 inspection_run_id: crawl_run_id,
                 candidate_count: bid_count,
                 notes:
                   "Configured from public procurement links found by bounded source inspection."
               }
             },
             actor: actor
           ) do
      {:ok, %{source: configured_source, mode: :auto_configured}}
    else
      0 -> {:error, "Inspection did not find any bid candidate links."}
      {:error, error} -> {:error, error}
    end
  end

  defp candidate_bid_count(candidates) do
    Enum.count(candidates, &(&1.candidate_type == :bid))
  end

  defp encode_lua_result(lua, value) do
    {encoded, lua} = Lua.encode!(lua, value)
    {[encoded], lua}
  end

  defp collect_messages(ref, acc) do
    receive do
      {^ref, kind, result} -> collect_messages(ref, [{kind, result} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp source_message(messages, kind) do
    case List.keyfind(messages, kind, 0) do
      {^kind, {:ok, result}} -> {:ok, result}
      {^kind, {:error, error}} -> {:error, error}
      nil -> {:error, "Source pipeline did not execute #{kind}."}
    end
  end

  defp source_context(source) do
    %{
      "id" => source.id,
      "name" => source.name,
      "url" => source.url,
      "source_type" => Atom.to_string(source.source_type),
      "config_status" => Atom.to_string(source.config_status),
      "requires_login" => source.requires_login
    }
  end

  defp serialize_inspection_result({:ok, result}) do
    inspection = result.inspection || %{}

    %{
      "ok" => true,
      "source_id" => result.source.id,
      "run_id" => result.run.id,
      "page_id" => result.page.id,
      "diagnosis" => inspection["diagnosis"],
      "requires_login" => truthy?(inspection["requires_login"]),
      "procurement_evidence" => truthy?(inspection["procurement_evidence"]),
      "public_listing_links" => inspection["public_listing_links"] || 0,
      "candidate_links" => inspection["candidate_links"] || 0,
      "password_inputs" => inspection["password_inputs"] || 0,
      "forms" => inspection["forms"] || 0
    }
  end

  defp serialize_inspection_result({:error, error}) do
    %{
      "ok" => false,
      "mode" => "inspection_failed",
      "error" => format_error(error)
    }
  end

  defp serialize_configuration_result({:ok, %{source: source, mode: mode}}) do
    %{
      "ok" => true,
      "source_id" => source.id,
      "mode" => Atom.to_string(mode),
      "config_status" => Atom.to_string(source.config_status)
    }
  end

  defp serialize_configuration_result({:error, error}) do
    %{
      "ok" => false,
      "mode" => "configuration_failed",
      "error" => format_error(error)
    }
  end

  defp fetch_source(%ProcurementSource{} = source, _actor), do: {:ok, source}

  defp fetch_source(id, actor) when is_binary(id) do
    Procurement.get_procurement_source(id, actor: actor)
  end

  defp normalize_lua_value(value) when is_list(value) do
    if Enum.all?(value, &match?({key, _value} when is_binary(key), &1)) do
      Map.new(value, fn {key, nested_value} -> {key, normalize_lua_value(nested_value)} end)
    else
      Enum.map(value, &normalize_lua_value/1)
    end
  end

  defp normalize_lua_value(value), do: value

  defp mode_atom("auto_configured"), do: :auto_configured
  defp mode_atom("already_configured"), do: :already_configured
  defp mode_atom("discovery_started"), do: :discovery_started
  defp mode_atom("already_pending"), do: :already_pending
  defp mode_atom("credentials_needed"), do: :credentials_needed
  defp mode_atom("inspection_failed"), do: :inspection_failed
  defp mode_atom("page_unavailable"), do: :page_unavailable
  defp mode_atom("inspected"), do: :inspected
  defp mode_atom(_mode), do: :unknown

  defp truthy?(true), do: true
  defp truthy?(_value), do: false

  defp put_pipeline(result, pipeline) when is_map(result),
    do: Map.put(result, :pipeline, pipeline)

  defp put_pipeline(result, pipeline), do: %{result: result, pipeline: pipeline}

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_exception(error), do: Exception.message(error)
  defp format_error(error), do: inspect(error)
end
