defmodule GnomeGarden.Acquisition.ProgramSourcePolicy do
  @moduledoc "Builds and validates immutable acquisition ProgramSource execution snapshots."

  @adapter "exa"
  @adapter_version "1"
  @capability_manifest ["exa.search", "exa.contents"]
  @enrichment_policies %{"none" => :none, "verify_promotable" => :verify_promotable}
  @snapshot_keys [
    "program_source_id",
    "source_id",
    "query_templates",
    "cadence_minutes",
    "max_queries_per_run",
    "max_results_per_query",
    "spend_limit_per_run",
    "spend_limit_per_day",
    "currency",
    "enrichment_policy",
    "max_enrichments_per_run",
    "finding_limit_per_run",
    "finding_limit_per_day",
    "adapter",
    "adapter_version",
    "capability_manifest"
  ]

  def snapshot(program_source) do
    snapshot = %{
      "program_source_id" => program_source.id,
      "source_id" => program_source.source_id,
      "query_templates" => program_source.query_templates,
      "cadence_minutes" => program_source.cadence_minutes,
      "max_queries_per_run" => program_source.max_queries_per_run,
      "max_results_per_query" => program_source.max_results_per_query,
      "spend_limit_per_run" => Decimal.to_string(program_source.spend_limit_per_run.amount),
      "spend_limit_per_day" => Decimal.to_string(program_source.spend_limit_per_day.amount),
      "currency" => to_string(program_source.spend_limit_per_run.currency),
      "enrichment_policy" => to_string(program_source.enrichment_policy),
      "max_enrichments_per_run" => program_source.max_enrichments_per_run,
      "finding_limit_per_run" => program_source.finding_limit_per_run,
      "finding_limit_per_day" => program_source.finding_limit_per_day,
      "adapter" => @adapter,
      "adapter_version" => @adapter_version,
      "capability_manifest" => @capability_manifest
    }

    Map.put(snapshot, "policy_hash", policy_hash(snapshot))
  end

  def execution_options(snapshot) when is_map(snapshot) do
    with :ok <- validate_snapshot(snapshot),
         {:ok, spend_ceiling} <- positive_float(snapshot, "spend_limit_per_run") do
      {:ok,
       [
         search_terms: snapshot["query_templates"],
         max_queries: snapshot["max_queries_per_run"],
         max_results_per_query: snapshot["max_results_per_query"],
         spend_ceiling: spend_ceiling,
         execution_policy_snapshot: snapshot
       ]}
    end
  end

  def verification_config(snapshot, thresholds) when is_map(snapshot) do
    with :ok <- validate_snapshot(snapshot),
         {:ok, enrichment_policy} <- enrichment_policy(snapshot),
         {:ok, candidate_limit} <- non_negative_integer(snapshot, "max_enrichments_per_run"),
         {:ok, finding_run_limit} <- non_negative_integer(snapshot, "finding_limit_per_run"),
         {:ok, finding_daily_limit} <- non_negative_integer(snapshot, "finding_limit_per_day") do
      {:ok,
       %{
         enrichment_policy: enrichment_policy,
         candidate_limit: candidate_limit,
         finding_run_limit: finding_run_limit,
         finding_daily_limit: finding_daily_limit,
         min_search_score: thresholds.min_search_score,
         min_evidence_characters: thresholds.min_evidence_characters
       }}
    end
  end

  def verification_config(_snapshot, _thresholds), do: {:error, :invalid_program_source_snapshot}

  defp validate_snapshot(snapshot) do
    with true <- is_binary(snapshot["program_source_id"]),
         true <- is_binary(snapshot["source_id"]),
         [_ | _] <- snapshot["query_templates"],
         {:ok, _value} <- positive_integer(snapshot, "max_queries_per_run"),
         {:ok, _value} <- positive_integer(snapshot, "max_results_per_query"),
         {:ok, _value} <- positive_float(snapshot, "spend_limit_per_run"),
         true <- snapshot["currency"] == "USD",
         true <- snapshot["adapter"] == @adapter,
         true <- snapshot["adapter_version"] == @adapter_version,
         true <- snapshot["capability_manifest"] == @capability_manifest,
         true <- valid_policy_hash?(snapshot) do
      :ok
    else
      _invalid -> {:error, :invalid_program_source_snapshot}
    end
  end

  defp valid_policy_hash?(%{"policy_hash" => policy_hash} = snapshot)
       when is_binary(policy_hash) do
    if byte_size(policy_hash) == 64 do
      snapshot
      |> Map.take(@snapshot_keys)
      |> policy_hash()
      |> Plug.Crypto.secure_compare(policy_hash)
    else
      false
    end
  end

  defp valid_policy_hash?(_snapshot), do: false

  defp enrichment_policy(snapshot) do
    case Map.get(@enrichment_policies, snapshot["enrichment_policy"]) do
      nil -> {:error, :invalid_program_source_snapshot}
      policy -> {:ok, policy}
    end
  end

  defp positive_integer(snapshot, key) do
    case snapshot[key] do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_program_source_snapshot}
    end
  end

  defp non_negative_integer(snapshot, key) do
    case snapshot[key] do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _invalid -> {:error, :invalid_program_source_snapshot}
    end
  end

  defp positive_float(snapshot, key) do
    case Float.parse(to_string(snapshot[key])) do
      {value, ""} when value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_program_source_snapshot}
    end
  end

  defp policy_hash(snapshot) do
    snapshot
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
