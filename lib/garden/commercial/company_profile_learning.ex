defmodule GnomeGarden.Commercial.CompanyProfileLearning do
  @moduledoc """
  Applies operator feedback back into the durable company profile.

  This keeps learned targeting decisions in the same profile structure that
  drives prompts, discovery scope, and procurement scoring.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.CompanyProfileContext
  alias GnomeGarden.Commercial.DefaultCompanyProfiles

  @learning_scopes ~w(out_of_scope not_targeting_right_now)
  @history_limit 50

  @spec record_targeting_feedback(keyword()) :: {:ok, map()} | {:error, term()}
  def record_targeting_feedback(opts) do
    with {:ok, profile} <- load_profile(Keyword.get(opts, :company_profile_key)),
         context <-
           CompanyProfileContext.resolve(
             profile: profile_to_map(profile),
             mode: Keyword.get(opts, :company_profile_mode)
           ),
         {:ok, updated_profile} <-
           Commercial.update_company_profile(
             profile,
             build_update_attrs(profile, context.company_profile_mode, opts)
           ) do
      {:ok,
       %{
         profile: updated_profile,
         company_profile_key: updated_profile.key,
         company_profile_mode: context.company_profile_mode,
         learned_terms: learned_terms(opts)
       }}
    end
  end

  defp load_profile(nil) do
    DefaultCompanyProfiles.ensure_default()
    Commercial.get_primary_company_profile()
  end

  defp load_profile(profile_key) when is_binary(profile_key) do
    case Commercial.get_company_profile_by_key(profile_key) do
      {:ok, profile} ->
        {:ok, profile}

      {:error, _error} ->
        load_profile(nil)
    end
  end

  defp build_update_attrs(profile, mode, opts) do
    feedback_scope = normalize_scope(Keyword.get(opts, :feedback_scope))
    learned_terms = learned_terms(opts)

    %{
      keyword_profiles:
        merge_keyword_profiles(
          profile.keyword_profiles || %{},
          mode,
          feedback_scope,
          learned_terms
        ),
      metadata:
        append_feedback_history(profile.metadata || %{}, %{
          "feedback_scope" => feedback_scope,
          "exclude_terms" => learned_terms,
          "reason" => normalize_text(Keyword.get(opts, :reason)),
          "source_type" => normalize_text(Keyword.get(opts, :source_type)),
          "source_id" => normalize_text(Keyword.get(opts, :source_id)),
          "recorded_at" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "company_profile_mode" => mode
        })
    }
  end

  defp merge_keyword_profiles(keyword_profiles, mode, feedback_scope, learned_terms) do
    if feedback_scope in @learning_scopes and learned_terms != [] do
      modes = Map.get(keyword_profiles, "modes", %{})
      mode_config = Map.get(modes, mode, %{})

      Map.put(
        keyword_profiles,
        "modes",
        Map.put(
          modes,
          mode,
          Map.put(
            mode_config,
            "learned_exclude",
            normalize_terms(Map.get(mode_config, "learned_exclude", []) ++ learned_terms)
          )
        )
      )
    else
      keyword_profiles
    end
  end

  defp append_feedback_history(metadata, entry) do
    history =
      metadata
      |> Map.get("targeting_feedback_history", [])
      |> List.wrap()
      |> Kernel.++([entry])
      |> Enum.take(-@history_limit)

    metadata
    |> Map.put("targeting_feedback_history", history)
    |> Map.put("last_targeting_feedback", entry)
  end

  defp learned_terms(opts) do
    opts
    |> Keyword.get(:exclude_terms, [])
    |> normalize_terms()
  end

  defp normalize_terms(values) do
    values
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_scope(nil), do: nil
  defp normalize_scope(value), do: value |> to_string() |> String.trim() |> blank_to_nil()

  defp normalize_text(nil), do: nil
  defp normalize_text(value), do: value |> to_string() |> String.trim() |> blank_to_nil()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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
end
