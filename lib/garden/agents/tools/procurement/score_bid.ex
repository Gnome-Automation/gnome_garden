defmodule GnomeGarden.Agents.Tools.Procurement.ScoreBid do
  @moduledoc """
  Score a bid opportunity against the shared market-focus model.

  This keeps procurement intake aligned with the actual service lane:
  controller-facing industrial integration first, with custom software and web
  work scoring well when it supports operations.
  """

  alias GnomeGarden.Commercial.MarketFocus

  def run(params, context) when is_map(context) do
    attrs =
      params
      |> maybe_put(:company_profile_key, context_value(context, [:company_profile_key]))
      |> maybe_put(
        :company_profile_key,
        context_value(context, [:deployment_config, :company_profile_key])
      )
      |> maybe_put(:company_profile_mode, context_value(context, [:company_profile_mode]))
      |> maybe_put(
        :company_profile_mode,
        context_value(context, [:source_scope, :company_profile_mode])
      )

    {:ok, MarketFocus.assess_bid(attrs)}
  end

  def run(params, _context) do
    {:ok, MarketFocus.assess_bid(params)}
  end

  defp context_value(context, path) do
    tool_context = Map.get(context, :tool_context, context)
    nested_value(tool_context, path)
  end

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    map
    |> nested_value([key])
    |> case do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp nested_value(_map, _path), do: nil

  defp maybe_put(params, _key, nil), do: params

  defp maybe_put(params, key, value) do
    case Map.get(params, key) do
      nil -> Map.put(params, key, value)
      "" -> Map.put(params, key, value)
      _ -> params
    end
  end
end
