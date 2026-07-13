defmodule GnomeGarden.Acquisition.FindingAdmissionPolicy do
  @moduledoc """
  Atomically admits one verified company candidate to the Finding review queue.

  Run and daily capacity, Finding creation, and the admission ledger commit in
  one database transaction. Unique normalized identities make retries and
  concurrent preview runs idempotent.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.{Finding, FindingAdmission, FindingAdmissionCapacity}
  alias GnomeGarden.Acquisition.LeadIdentity
  alias GnomeGarden.Acquisition.Support

  def admit(verification, candidate, preview_run, program, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:second)
    identity_key = LeadIdentity.company_domain_key(verification.website_domain)

    case Acquisition.get_finding_admission_by_identity(identity_key, actor: actor) do
      {:ok, admission} ->
        {:ok, %{admission: admission, reused?: true}}

      {:error, _not_found} ->
        create_admission(verification, candidate, preview_run, program, identity_key, now, opts)
    end
  end

  def capacity_exceeded?(error) do
    error
    |> Support.errors()
    |> Enum.any?(fn
      %GnomeGarden.Acquisition.Errors.FindingAdmissionCapacityExceeded{} -> true
      _error -> false
    end)
  end

  defp create_admission(verification, candidate, preview_run, program, identity_key, now, opts) do
    actor = Keyword.get(opts, :actor)
    run_limit = Keyword.fetch!(opts, :run_limit)
    daily_limit = Keyword.fetch!(opts, :daily_limit)
    {day_started_at, day_resets_at, day_key} = day_window(now, preview_run)

    result =
      Support.transact([FindingAdmissionCapacity, Finding, FindingAdmission], fn ->
        with {:ok, run_capacity} <- open_run_capacity(preview_run, run_limit, actor),
             {:ok, day_capacity} <-
               open_day_capacity(day_key, day_started_at, day_resets_at, daily_limit, actor),
             {:ok, _run_capacity} <-
               Acquisition.consume_finding_admission_capacity(run_capacity, actor: actor),
             {:ok, _day_capacity} <-
               Acquisition.consume_finding_admission_capacity(day_capacity, actor: actor),
             {:ok, finding} <-
               create_finding(
                 verification,
                 candidate,
                 preview_run,
                 program,
                 identity_key,
                 now,
                 actor
               ),
             {:ok, admission} <-
               Acquisition.create_finding_admission(
                 %{
                   lead_candidate_verification_id: verification.id,
                   lead_preview_candidate_id: candidate.id,
                   lead_preview_run_id: preview_run.id,
                   finding_id: finding.id,
                   identity_key: identity_key,
                   admitted_at: now,
                   metadata: %{
                     "run_capacity_id" => run_capacity.id,
                     "day_capacity_id" => day_capacity.id
                   }
                 },
                 actor: actor
               ) do
          {:ok, %{admission: admission, finding: finding, reused?: false}}
        end
      end)

    case result do
      {:error, error} -> reuse_after_conflict(error, identity_key, actor)
      success -> success
    end
  end

  defp open_run_capacity(preview_run, admission_limit, actor) do
    Acquisition.open_finding_admission_capacity(
      %{
        scope: :run,
        scope_key: preview_run.id,
        window_started_at: preview_run.started_at || preview_run.inserted_at,
        resets_at: nil,
        admission_limit: admission_limit
      },
      actor: actor
    )
  end

  defp open_day_capacity(day_key, started_at, resets_at, admission_limit, actor) do
    Acquisition.open_finding_admission_capacity(
      %{
        scope: :day,
        scope_key: day_key,
        window_started_at: started_at,
        resets_at: resets_at,
        admission_limit: admission_limit
      },
      actor: actor
    )
  end

  defp create_finding(verification, candidate, preview_run, program, identity_key, now, actor) do
    evidence = verification.evidence
    excerpt = get_in(evidence, ["citations", Access.at(0), "excerpt"])
    summary = evidence["summary"] || excerpt || candidate.recommendation

    Acquisition.create_finding(
      %{
        title: candidate.title || verification.website_domain,
        summary: summary,
        external_ref: identity_key,
        source_url: candidate.url,
        finding_family: :discovery,
        finding_type: :company_signal,
        status: :new,
        work_summary: summary,
        fit_score: verification.verification_score,
        score_tier: score_tier(verification.verification_score),
        intent_score: verification.verification_score,
        confidence: confidence(verification.verification_score),
        recommendation: "Review verified commercial company lead.",
        observed_at: now,
        program_id: program.id,
        source_id: preview_run.metadata["source_id"],
        program_source_id: preview_run.metadata["program_source_id"],
        metadata: %{
          "lead_preview_run_id" => preview_run.id,
          "lead_preview_candidate_id" => candidate.id,
          "lead_candidate_verification_id" => verification.id,
          "website_domain" => verification.website_domain,
          "query" => candidate.query,
          "dedupe_context" => to_string(candidate.dedupe_context),
          "evidence" => evidence
        }
      },
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_external_ref,
      upsert_fields: []
    )
  end

  defp score_tier(score) when score >= 80, do: :hot
  defp score_tier(score) when score >= 60, do: :warm
  defp score_tier(_score), do: :prospect

  defp confidence(score) when score >= 80, do: :high
  defp confidence(score) when score >= 60, do: :medium
  defp confidence(_score), do: :low

  defp day_window(now, preview_run) do
    started_at = DateTime.new!(DateTime.to_date(now), ~T[00:00:00], "Etc/UTC")

    day_key =
      "#{preview_run.metadata["program_source_id"]}:#{Date.to_iso8601(DateTime.to_date(started_at))}"

    {started_at, DateTime.add(started_at, 1, :day), day_key}
  end

  defp reuse_after_conflict(error, identity_key, actor) do
    case Acquisition.get_finding_admission_by_identity(identity_key, actor: actor) do
      {:ok, admission} -> {:ok, %{admission: admission, reused?: true}}
      {:error, _not_found} -> {:error, error}
    end
  end
end
