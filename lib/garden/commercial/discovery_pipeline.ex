defmodule GnomeGarden.Commercial.DiscoveryPipeline do
  @moduledoc """
  Bounded live-search orchestration for commercial discovery programs.

  Production execution performs preview-safe Exa search and persists candidate
  telemetry without creating findings or downstream commercial records. The
  previous AshLua seed path remains available only as an explicit test fixture.
  """

  alias GnomeGarden.Agents.Tools.Commercial.SaveDiscoveryFinding
  alias GnomeGarden.Acquisition.LeadPreview
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryProgram

  @scan_script """
  local candidates = program_context.candidates or {}
  local saved = 0
  local failed = 0
  local results = {}

  for index, candidate in ipairs(candidates) do
    local result = discovery.save_candidate(candidate)
    results[index] = result

    if result.ok then
      saved = saved + 1
    else
      failed = failed + 1
    end
  end

  return {
    ok = failed == 0,
    mode = #candidates == 0 and "no_candidates" or "processed_seed_candidates",
    candidate_count = #candidates,
    saved = saved,
    failed = failed,
    results = results
  }
  """

  @type pipeline_result :: {:ok, map()} | {:error, term()}

  @doc "Describes the candidate source used by scheduled discovery execution."
  @spec execution_profile() :: map()
  def execution_profile do
    %{
      mode: :live_exa_preview,
      live_search?: true,
      candidate_source: :exa,
      preview_only?: true
    }
  end

  @spec run_program(DiscoveryProgram.t() | Ecto.UUID.t(), keyword()) :: pipeline_result
  def run_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, program} <- fetch_program(program_or_id, actor),
         {:ok, preview} <-
           LeadPreview.run_for_program(
             program,
             actor: actor,
             discovery_program_id: program.id,
             persist: true
           ),
         {:ok, _program} <- Commercial.mark_discovery_program_ran(program, actor: actor) do
      {:ok, Map.merge(preview, %{program: program, mode: :live_exa_preview})}
    end
  end

  @doc "Runs the legacy seed-candidate path explicitly for fixture coverage."
  @spec run_seed_fixture(DiscoveryProgram.t() | Ecto.UUID.t(), keyword()) :: pipeline_result
  def run_seed_fixture(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, program} <- fetch_program(program_or_id, actor),
         {:ok, script_result, messages} <- run_lua(program, opts),
         {:ok, _program} <- Commercial.mark_discovery_program_ran(program, actor: actor) do
      {:ok,
       %{
         program: program,
         mode: script_result["mode"],
         candidate_count: script_result["candidate_count"] || 0,
         saved: script_result["saved"] || 0,
         failed: script_result["failed"] || 0,
         results: discovery_messages(messages),
         pipeline: script_result
       }}
    end
  end

  defp fetch_program(%DiscoveryProgram{id: id}, actor), do: fetch_program(id, actor)

  defp fetch_program(id, actor) when is_binary(id),
    do: Commercial.get_discovery_program(id, actor: actor)

  defp run_lua(program, opts) do
    actor = Keyword.get(opts, :actor)
    ref = make_ref()
    caller = self()

    lua =
      Lua.new()
      |> Lua.set!([:program_context], program_context(program))
      |> Lua.set!(
        [:discovery, :save_candidate],
        save_candidate_function(ref, caller, program, actor)
      )
      |> then(
        &AshLua.new(otp_app: :gnome_garden, actor: actor, context: lua_context(opts), lua: &1)
      )

    try do
      {[raw_result], _lua} = Lua.eval!(lua, @scan_script)
      {:ok, normalize_lua_value(raw_result), collect_messages(ref, [])}
    rescue
      error in [Lua.CompilerException, Lua.RuntimeException] ->
        {:error, Exception.message(error)}
    end
  end

  defp lua_context(opts) do
    opts
    |> Keyword.get(:context, %{})
    |> case do
      context when is_map(context) -> context
      _other -> %{}
    end
    |> Map.put(:commercial_discovery_pipeline?, true)
  end

  defp save_candidate_function(ref, caller, program, actor) do
    fn [candidate], lua ->
      decoded_candidate = Lua.decode!(lua, candidate)
      params = candidate_params(decoded_candidate, program)
      result = SaveDiscoveryFinding.run(params, %{actor: actor, discovery_program_id: program.id})
      send(caller, {ref, :candidate, result})
      encode_lua_result(lua, serialize_candidate_result(result))
    end
  end

  defp candidate_params(candidate, program) do
    normalized_candidate = normalize_lua_value(candidate)

    normalized_candidate
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
    |> Map.put_new(:discovery_program_id, program.id)
    |> Map.put_new(
      :source_url,
      map_value(normalized_candidate, "source_url") || map_value(normalized_candidate, :website)
    )
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "company_name" -> :company_name
      "website" -> :website
      "location" -> :location
      "industry" -> :industry
      "employee_count" -> :employee_count
      "signal" -> :signal
      "company_description" -> :company_description
      "source_url" -> :source_url
      "contact_first_name" -> :contact_first_name
      "contact_last_name" -> :contact_last_name
      "contact_email" -> :contact_email
      "contact_phone" -> :contact_phone
      "contact_title" -> :contact_title
      "discovery_program_id" -> :discovery_program_id
      other -> other
    end
  end

  defp program_context(program) do
    metadata = program.metadata || %{}

    %{
      "id" => program.id,
      "name" => program.name,
      "target_regions" => program.target_regions || [],
      "target_industries" => program.target_industries || [],
      "search_terms" => program.search_terms || [],
      "candidates" =>
        Map.get(metadata, "seed_candidates") || Map.get(metadata, :seed_candidates) || []
    }
  end

  defp discovery_messages(messages) do
    messages
    |> Enum.filter(fn {kind, _result} -> kind == :candidate end)
    |> Enum.map(fn {_kind, result} -> serialize_candidate_result(result) end)
  end

  defp collect_messages(ref, acc) do
    receive do
      {^ref, kind, result} -> collect_messages(ref, [{kind, result} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp serialize_candidate_result({:ok, result}) do
    %{
      ok: true,
      saved: Map.get(result, :saved, false),
      organization_id: Map.get(result, :organization_id),
      discovery_record_id: Map.get(result, :discovery_record_id),
      evidence_id: Map.get(result, :evidence_id),
      finding_id: Map.get(result, :finding_id),
      company: Map.get(result, :company),
      message: Map.get(result, :message)
    }
  end

  defp serialize_candidate_result({:error, reason}) do
    %{ok: false, error: inspect(reason)}
  end

  defp encode_lua_result(lua, value) do
    {encoded, lua} = Lua.encode!(lua, value)
    {[encoded], lua}
  end

  defp normalize_lua_value(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {key, normalize_lua_value(value)} end)
  end

  defp normalize_lua_value(value) when is_list(value) do
    cond do
      Enum.all?(value, &match?({key, _value} when is_binary(key), &1)) ->
        Map.new(value, fn {key, nested_value} -> {key, normalize_lua_value(nested_value)} end)

      Enum.all?(value, &match?({_key, _value}, &1)) ->
        Map.new(value, fn {key, nested_value} -> {key, normalize_lua_value(nested_value)} end)

      true ->
        Enum.map(value, &normalize_lua_value/1)
    end
  end

  defp normalize_lua_value(value), do: value

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp map_value(_map, _key), do: nil
end
