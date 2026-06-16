defmodule GnomeGarden.Procurement.Actions.ImportProcurementSources do
  @moduledoc """
  Imports procurement source seed rows through the Procurement domain boundary.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Procurement

  @atom_fields %{
    source_type: [
      :planetbids,
      :opengov,
      :bidnet,
      :sam_gov,
      :cal_eprocure,
      :utility,
      :school,
      :port,
      :custom,
      :company_site,
      :job_board,
      :directory
    ],
    region: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national],
    priority: [:high, :medium, :low],
    status: [:candidate, :approved, :ignored, :blocked]
  }

  @impl true
  def run(input, _opts, context) do
    rows = Ash.ActionInput.get_argument(input, :rows) || []
    actor = context.actor

    result =
      Enum.reduce(rows, empty_result(), fn row, acc ->
        row
        |> stringify_keys()
        |> import_row!(actor)
        |> merge_result(acc)
      end)

    {:ok, result}
  rescue
    error -> {:error, error}
  end

  defp empty_result do
    %{
      "imported_count" => 0,
      "created_count" => 0,
      "updated_count" => 0,
      "configured_count" => 0,
      "manual_count" => 0,
      "source_ids" => []
    }
  end

  defp merge_result(row_result, acc) do
    acc
    |> increment("imported_count")
    |> increment(if(row_result.created?, do: "created_count", else: "updated_count"))
    |> maybe_increment("configured_count", row_result.configured?)
    |> maybe_increment("manual_count", row_result.manual?)
    |> Map.update!("source_ids", &[row_result.source.id | &1])
  end

  defp import_row!(row, actor) do
    existing = existing_source(row, actor)

    source =
      if existing do
        update_existing_source!(existing, row, actor)
      else
        create_source!(row, actor)
      end

    {source, transition} = apply_config_status_hint!(source, row, actor)

    %{
      source: source,
      created?: is_nil(existing),
      configured?: transition == :configured,
      manual?: transition == :manual
    }
  end

  defp existing_source(row, actor) do
    case Procurement.get_procurement_source_by_url(fetch_string!(row, "url"),
           actor: actor,
           authorize?: false
         ) do
      {:ok, source} ->
        source

      {:error, error} ->
        if not_found_error?(error) do
          nil
        else
          raise "Failed to load procurement source #{Map.get(row, "url")}: #{Exception.message(error)}"
        end
    end
  end

  defp create_source!(row, actor) do
    {:ok, source} =
      row
      |> create_attrs()
      |> Procurement.create_procurement_source(actor: actor, authorize?: false)

    source
  end

  defp update_existing_source!(source, row, actor) do
    attrs =
      %{
        name: fetch_string!(row, "name"),
        url: fetch_string!(row, "url"),
        priority: normalize_atom!(:priority, Map.get(row, "priority")),
        enabled: parse_boolean(Map.get(row, "enabled")),
        requires_login: parse_boolean(Map.get(row, "requires_login")),
        scan_frequency_hours: parse_integer(Map.get(row, "scan_frequency_hours")),
        status: normalize_atom!(:status, Map.get(row, "status")),
        metadata: deep_merge(source.metadata || %{}, import_metadata(row))
      }
      |> reject_nil_values()

    {:ok, source} =
      Procurement.update_procurement_source(source, attrs, actor: actor, authorize?: false)

    source
  end

  defp create_attrs(row) do
    %{
      name: fetch_string!(row, "name"),
      url: fetch_string!(row, "url"),
      source_type: normalize_atom!(:source_type, Map.get(row, "source_type")),
      portal_id: blank_to_nil(Map.get(row, "portal_id")),
      region: normalize_atom!(:region, Map.get(row, "region")),
      priority: normalize_atom!(:priority, Map.get(row, "priority")),
      api_available: parse_boolean(Map.get(row, "api_available")),
      requires_login: parse_boolean(Map.get(row, "requires_login")),
      scan_frequency_hours: parse_integer(Map.get(row, "scan_frequency_hours")),
      enabled: parse_boolean(Map.get(row, "enabled")),
      status: normalize_atom!(:status, Map.get(row, "status")),
      added_by: :import,
      notes: blank_to_nil(Map.get(row, "notes")),
      metadata: import_metadata(row)
    }
    |> reject_nil_values()
  end

  defp import_metadata(row) do
    row
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "metadata_") end)
    |> Map.new(fn {key, value} ->
      {String.replace_prefix(key, "metadata_", ""), blank_to_nil(value)}
    end)
    |> reject_nil_values()
    |> then(fn metadata ->
      %{
        "seed_import" =>
          metadata
          |> Map.put("config_status_hint", blank_to_nil(Map.get(row, "config_status_hint")))
          |> Map.put(
            "imported_at",
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
          )
      }
    end)
  end

  defp apply_config_status_hint!(source, row, actor) do
    case blank_to_nil(Map.get(row, "config_status_hint")) do
      "configured" ->
        configure_source!(source, actor)

      "manual" ->
        set_manual_source!(source, actor)

      _other ->
        {source, nil}
    end
  end

  defp configure_source!(%{config_status: :configured} = source, _actor), do: {source, nil}
  defp configure_source!(%{config_status: :scan_failed} = source, _actor), do: {source, nil}

  defp configure_source!(source, actor) do
    {:ok, source} =
      Procurement.configure_procurement_source(
        source,
        %{scrape_config: source.scrape_config || %{}},
        actor: actor,
        authorize?: false
      )

    {source, :configured}
  end

  defp set_manual_source!(%{config_status: :manual} = source, _actor), do: {source, nil}
  defp set_manual_source!(%{config_status: :configured} = source, _actor), do: {source, nil}
  defp set_manual_source!(%{config_status: :scan_failed} = source, _actor), do: {source, nil}

  defp set_manual_source!(source, actor) do
    {:ok, source} =
      Procurement.set_manual_procurement_source(
        source,
        %{scrape_config: source.scrape_config || %{}},
        actor: actor,
        authorize?: false
      )

    {source, :manual}
  end

  defp normalize_atom!(field, value) do
    allowed = Map.fetch!(@atom_fields, field)

    cond do
      is_atom(value) and value in allowed ->
        value

      is_binary(value) ->
        normalized = value |> String.trim() |> String.downcase()
        Enum.find(allowed, &(Atom.to_string(&1) == normalized)) || raise_invalid(field, value)

      true ->
        raise_invalid(field, value)
    end
  end

  defp parse_boolean(value) when is_boolean(value), do: value

  defp parse_boolean(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "true" -> true
      "false" -> false
      "" -> nil
      other -> raise "Invalid boolean value: #{inspect(other)}"
    end
  end

  defp parse_boolean(nil), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp parse_integer(nil), do: nil

  defp fetch_string!(row, key) do
    case blank_to_nil(Map.get(row, key)) do
      nil -> raise "Missing required procurement source field #{key}"
      value -> value
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp increment(map, key), do: Map.update!(map, key, &(&1 + 1))

  defp maybe_increment(map, key, true), do: increment(map, key)
  defp maybe_increment(map, _key, _false), do: map

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp not_found_error?(%Ash.Error.Query.NotFound{}), do: true

  defp not_found_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  defp not_found_error?(_error), do: false

  defp raise_invalid(field, value) do
    raise "Invalid procurement source #{field}: #{inspect(value)}"
  end
end
