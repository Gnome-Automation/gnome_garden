defmodule GnomeGarden.Agents.Tools.Procurement.ScoreBid do
  @moduledoc """
  Score a bid opportunity against the shared market-focus model.

  This keeps procurement intake aligned with the actual service lane:
  controller-facing industrial integration first, with custom software and web
  work scoring well when it supports operations.
  """

  use Jido.Action,
    name: "score_bid",
    description: "Score a bid opportunity using shared procurement and discovery heuristics",
    schema: [
      title: [type: :string, required: true, doc: "Bid title"],
      description: [type: :string, doc: "Bid description or synopsis"],
      location: [type: :string, doc: "Location (city, state)"],
      region: [type: :atom, doc: "Region code"],
      estimated_value: [type: :float, doc: "Estimated contract value in dollars"],
      agency: [type: :string, doc: "Issuing agency name"],
      keywords: [type: {:array, :string}, default: [], doc: "Keywords found in the bid"],
      company_profile_key: [type: :string, doc: "Optional company profile key override"],
      company_profile_mode: [type: :string, doc: "Optional company profile mode override"],
      source_type: [type: :atom, doc: "Procurement source family"],
      source_name: [type: :string, doc: "Human-readable source name"],
      source_url: [type: :string, doc: "Originating listing URL"]
    ]

  alias GnomeGarden.Commercial.MarketFocus

  @impl true
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
