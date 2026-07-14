defmodule GnomeGarden.AcquisitionEvaluationCorpus do
  @moduledoc false

  @root Path.expand("../fixtures/acquisition_eval/v1", __DIR__)
  @manifest_path Path.join(@root, "manifest.json")

  @atoms %{
    "accepted" => :accepted,
    "auth" => :auth,
    "bidnet" => :bidnet,
    "company" => :company,
    "contents" => :contents,
    "custom" => :custom,
    "duplicate" => :duplicate,
    "duplicate_existing_lead" => :duplicate_existing_lead,
    "exa" => :exa,
    "existing_bid_related" => :existing_bid_related,
    "jido" => :jido,
    "known_bid_source" => :known_bid_source,
    "known_organization_new_signal" => :known_organization_new_signal,
    "known_procurement_source" => :known_procurement_source,
    "listings" => :listings,
    "malformed" => :malformed,
    "needs_enrichment" => :needs_enrichment,
    "new" => :new,
    "opengov" => :opengov,
    "playwright" => :playwright,
    "promote" => :promote,
    "promoted" => :promoted,
    "provider_action" => :provider_action,
    "projects" => :projects,
    "rejected" => :rejected,
    "schema_drift" => :schema_drift,
    "search" => :search,
    "signal" => :signal,
    "skip" => :skip,
    "suppressed" => :suppressed,
    "throttled" => :throttled,
    "timeout" => :timeout,
    "waf" => :waf,
    "web_fetch" => :web_fetch
  }

  def load do
    @manifest_path
    |> File.read!()
    |> Jason.decode!()
  end

  def exa_response do
    load()
    |> Map.fetch!("exa_fixture")
    |> then(&Path.join(@root, &1))
    |> File.read!()
    |> Jason.decode!()
  end

  def candidate_expectations do
    load()
    |> Map.fetch!("candidate_expectations")
    |> Enum.map(fn expectation ->
      %{
        url: expectation["url"],
        historical_outcome: atom!(expectation["historical_outcome"]),
        candidate_type: atom!(expectation["candidate_type"]),
        dedupe_context: atom!(expectation["dedupe_context"]),
        route: atom!(expectation["route"]),
        suppressed: expectation["suppressed"],
        rank: expectation["rank"]
      }
    end)
  end

  def provider_failure_cases do
    load()
    |> Map.fetch!("provider_failure_cases")
    |> Enum.map(fn failure ->
      %{
        provider: atom!(failure["provider"]),
        operation: atom!(failure["operation"]),
        scenario: atom!(failure["scenario"])
      }
    end)
  end

  def atom!(name), do: Map.fetch!(@atoms, name)
end
