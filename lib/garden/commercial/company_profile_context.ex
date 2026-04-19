defmodule GnomeGarden.Commercial.CompanyProfileContext do
  @moduledoc """
  Read helper that turns the primary company profile into runtime-safe context.

  This module is intentionally tolerant: if the durable profile record is not
  available yet, it falls back to the seeded default attributes so prompts and
  deployment defaults still have a sensible baseline.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DefaultCompanyProfiles

  @default_profile DefaultCompanyProfiles.primary_profile_attrs()
  @default_bidnet_queries ["scada", "plc", "controls"]
  @default_sam_gov_naics_codes ["541330", "541512"]

  @spec primary_profile() :: map()
  def primary_profile, do: profile(nil)

  @spec profile(String.t() | nil) :: map()
  def profile(nil) do
    case Commercial.get_primary_company_profile() do
      {:ok, profile} -> profile_to_map(profile)
      _ -> @default_profile
    end
  end

  def profile(key) when is_binary(key) do
    case Commercial.get_company_profile_by_key(key) do
      {:ok, profile} -> profile_to_map(profile)
      _ -> @default_profile
    end
  end

  @spec profile_mode(map() | nil) :: atom()
  def profile_mode(profile \\ nil) do
    profile = profile || primary_profile()
    Map.get(profile, :default_profile_mode, :industrial_plus_software)
  end

  @spec keyword_mode(map() | nil, atom() | String.t() | nil) :: map()
  def keyword_mode(profile \\ nil, mode \\ nil) do
    profile = profile || primary_profile()
    mode_key = mode_key(mode || profile_mode(profile))

    get_in(profile, [:keyword_profiles, "modes", mode_key]) || %{}
  end

  @spec resolve(keyword() | map() | nil) :: map()
  def resolve(opts_or_map \\ nil)

  def resolve(nil), do: resolved_profile([])

  def resolve(opts) when is_list(opts), do: resolved_profile(opts)

  def resolve(%{} = attrs) do
    resolved_profile(
      profile_key: map_value(attrs, :company_profile_key),
      mode: map_value(attrs, :company_profile_mode)
    )
  end

  @spec bid_scanner_keywords(map() | nil, atom() | String.t() | nil) :: [String.t()]
  def bid_scanner_keywords(profile \\ nil, mode \\ nil) do
    profile = profile || primary_profile()

    profile
    |> keyword_mode(mode)
    |> Map.get("include", [])
    |> normalize_terms()
  end

  @spec prompt_block(keyword()) :: String.t()
  def prompt_block(opts \\ []) do
    resolved = resolve(opts)
    profile = resolved.profile

    """
    COMPANY PROFILE
    - Name: #{Map.get(profile, :name)}
    - Positioning: #{Map.get(profile, :positioning_summary)}
    - Specialty: #{Map.get(profile, :specialty_summary)}
    - Core capabilities: #{render_list(Map.get(profile, :core_capabilities, []), "None")}
    - Adjacent capabilities: #{render_list(Map.get(profile, :adjacent_capabilities, []), "None")}
    - Target industries: #{render_list(Map.get(profile, :target_industries, []), "None")}
    - Preferred engagements: #{render_list(Map.get(profile, :preferred_engagements, []), "None")}
    - Disqualifiers: #{render_list(Map.get(profile, :disqualifiers, []), "None")}
    - Voice: #{Map.get(profile, :voice_summary)}
    - Voice principles: #{render_list(Map.get(profile, :voice_principles, []), "None")}
    - Active profile mode: #{resolved.company_profile_mode}
    - Mode include keywords: #{render_list(resolved.include_keywords, "None")}
    - Mode exclude keywords: #{render_list(resolved.exclude_keywords, "None")}
    """
    |> String.trim()
  end

  @spec deployment_scope(keyword()) :: map()
  def deployment_scope(opts \\ []) do
    resolved = resolve(opts)
    profile = resolved.profile

    %{
      company_profile_key: resolved.company_profile_key,
      company_profile_mode: resolved.company_profile_mode,
      target_industries: Map.get(profile, :target_industries, []),
      preferred_engagements: Map.get(profile, :preferred_engagements, []),
      keywords: resolved.include_keywords,
      bidnet_query_keywords: resolved.bidnet_query_keywords,
      sam_gov_naics_codes: resolved.sam_gov_naics_codes,
      notes: Map.get(profile, :specialty_summary)
    }
  end

  @spec bidnet_query_keywords(map() | nil, atom() | String.t() | nil) :: [String.t()]
  def bidnet_query_keywords(profile \\ nil, mode \\ nil) do
    profile = profile || primary_profile()

    profile
    |> keyword_mode(mode)
    |> Map.get("bidnet_queries", default_bidnet_queries(mode))
    |> normalize_terms()
  end

  @spec sam_gov_naics_codes(map() | nil, atom() | String.t() | nil) :: [String.t()]
  def sam_gov_naics_codes(profile \\ nil, mode \\ nil) do
    profile = profile || primary_profile()

    profile
    |> keyword_mode(mode)
    |> Map.get("sam_gov_naics_codes", default_sam_gov_naics_codes(mode))
    |> normalize_terms()
  end

  defp profile_to_map(profile) do
    %{
      key: profile.key,
      name: profile.name,
      legal_name: profile.legal_name,
      positioning_summary: profile.positioning_summary,
      specialty_summary: profile.specialty_summary,
      voice_summary: profile.voice_summary,
      core_capabilities: profile.core_capabilities || [],
      adjacent_capabilities: profile.adjacent_capabilities || [],
      target_industries: profile.target_industries || [],
      preferred_engagements: profile.preferred_engagements || [],
      disqualifiers: profile.disqualifiers || [],
      voice_principles: profile.voice_principles || [],
      preferred_phrases: profile.preferred_phrases || [],
      avoid_phrases: profile.avoid_phrases || [],
      default_profile_mode: profile.default_profile_mode,
      keyword_profiles: profile.keyword_profiles || %{},
      metadata: profile.metadata || %{}
    }
  end

  defp mode_key(mode) when is_atom(mode), do: Atom.to_string(mode)
  defp mode_key(mode) when is_binary(mode), do: mode
  defp mode_key(_mode), do: "industrial_plus_software"

  defp resolved_profile(opts) do
    requested_key = normalize_blank(Keyword.get(opts, :profile_key))
    requested_mode = Keyword.get(opts, :mode)
    profile = Keyword.get(opts, :profile) || profile(requested_key)
    mode = mode_key(requested_mode || profile_mode(profile))
    keyword_mode = keyword_mode(profile, mode)

    %{
      profile: profile,
      company_profile_key: Map.get(profile, :key, "primary"),
      company_profile_mode: mode,
      keyword_mode: keyword_mode,
      include_keywords: normalize_terms(Map.get(keyword_mode, "include", [])),
      exclude_keywords:
        normalize_terms(
          Map.get(keyword_mode, "exclude", []) ++ Map.get(keyword_mode, "learned_exclude", [])
        ),
      bidnet_query_keywords:
        normalize_terms(Map.get(keyword_mode, "bidnet_queries", default_bidnet_queries(mode))),
      sam_gov_naics_codes:
        normalize_terms(
          Map.get(keyword_mode, "sam_gov_naics_codes", default_sam_gov_naics_codes(mode))
        ),
      target_industries: Map.get(profile, :target_industries, []),
      preferred_engagements: Map.get(profile, :preferred_engagements, [])
    }
  end

  defp default_bidnet_queries("industrial_core"),
    do: ["scada", "plc", "controls", "instrumentation", "automation"]

  defp default_bidnet_queries("broad_software"),
    do: ["custom software", "web application", "workflow software"]

  defp default_bidnet_queries(_mode), do: @default_bidnet_queries ++ ["automation", "integration"]

  defp default_sam_gov_naics_codes("industrial_core"), do: ["541330", "238210"]
  defp default_sam_gov_naics_codes("broad_software"), do: ["541511", "541512", "541519"]
  defp default_sam_gov_naics_codes(_mode), do: @default_sam_gov_naics_codes ++ ["541519"]

  defp normalize_terms(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp map_value(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_blank(nil), do: nil
  defp normalize_blank(value) when is_binary(value), do: String.trim(value) |> blank_to_nil()
  defp normalize_blank(value), do: value |> to_string() |> normalize_blank()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp render_list([], empty), do: empty
  defp render_list(items, _empty), do: Enum.map_join(items, ", ", &to_string/1)
end
