defmodule GnomeGarden.Calculations.AcquisitionSourceHealth do
  @moduledoc """
  Derives acquisition-native source health semantics from run state and finding mix.
  """

  use Ash.Resource.Calculation

  @default_stale_after_hours 168

  @impl true
  def init(opts) do
    return = Keyword.get(opts, :return, :status)

    if return in [:status, :note] do
      {:ok, Keyword.put_new(opts, :stale_after_hours, @default_stale_after_hours)}
    else
      {:error, "`return` must be :status or :note"}
    end
  end

  @impl true
  def load(_query, _opts, _context) do
    [
      :enabled,
      :last_run_at,
      :last_success_at,
      :metadata,
      :noise_finding_count,
      :promoted_finding_count,
      :review_finding_count,
      :scan_strategy,
      :status
    ]
  end

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      health_status = health_status(record, opts)

      case Keyword.fetch!(opts, :return) do
        :status -> health_status
        :note -> health_note(record, health_status, opts)
      end
    end)
  end

  defp health_status(source, opts) do
    run_state = last_run_state(source)

    cond do
      source.status == :archived -> :archived
      source.status == :blocked -> :blocked
      source.status == :paused -> :paused
      source.enabled == false -> :disabled
      needs_login?(source) -> :needs_login
      run_state == :running -> :running
      run_state == :failed -> :failing
      run_state == :cancelled -> :cancelled
      scan_issue(source) == :login_required -> :needs_login
      scan_issue(source) == :document_capture_failed -> :document_capture_failed
      scan_issue(source) == :selector_failed -> :selector_failed
      scan_issue(source) == :no_results -> :no_results
      scan_issue(source) == :zero_saved -> :zero_saved
      noisy?(source) -> :noisy
      source.scan_strategy == :manual -> :manual
      stale?(source, opts) -> :stale
      source.status in [:active, :candidate] -> :healthy
      true -> :idle
    end
  end

  defp health_note(_source, :archived, _opts), do: "Archived source."
  defp health_note(_source, :blocked, _opts), do: "Blocked until operator repair."
  defp health_note(_source, :paused, _opts), do: "Paused and out of rotation."
  defp health_note(_source, :disabled, _opts), do: "Disabled and not launchable."
  defp health_note(source, :needs_login, _opts), do: missing_credentials_note(source)
  defp health_note(_source, :running, _opts), do: "Run currently in progress."
  defp health_note(source, :document_capture_failed, _opts), do: scan_issue_note(source)
  defp health_note(source, :selector_failed, _opts), do: scan_issue_note(source)
  defp health_note(source, :no_results, _opts), do: scan_issue_note(source)
  defp health_note(source, :zero_saved, _opts), do: scan_issue_note(source)

  defp health_note(source, :failing, _opts),
    do: timestamp_note("Last run failed", source.last_run_at)

  defp health_note(source, :cancelled, _opts),
    do: timestamp_note("Last run was cancelled", source.last_run_at)

  defp health_note(source, :noisy, _opts) do
    "#{source.noise_finding_count || 0} noise vs #{productive_finding_count(source)} productive findings."
  end

  defp health_note(_source, :manual, _opts), do: "Manual source with no expected scan cadence."

  defp health_note(source, :stale, _opts) do
    cond do
      source.last_success_at ->
        timestamp_note("Last successful scan", source.last_success_at)

      source.last_run_at ->
        timestamp_note("No successful scan since", source.last_run_at)

      true ->
        "No successful scan recorded yet."
    end
  end

  defp health_note(source, :healthy, _opts) do
    cond do
      source.last_success_at ->
        timestamp_note("Last successful scan", source.last_success_at)

      source.last_run_at ->
        timestamp_note("Last run completed", source.last_run_at)

      true ->
        "Ready for acquisition work."
    end
  end

  defp health_note(_source, :idle, _opts), do: "Awaiting activation."

  defp last_run_state(%{metadata: metadata}) when is_map(metadata) do
    metadata
    |> Map.get("last_agent_run_state", Map.get(metadata, :last_agent_run_state))
    |> normalize_run_state()
  end

  defp last_run_state(_source), do: nil

  defp normalize_run_state(value) when is_atom(value), do: value

  defp normalize_run_state(value) when is_binary(value) do
    case value do
      "completed" -> :completed
      "running" -> :running
      "failed" -> :failed
      "cancelled" -> :cancelled
      _ -> nil
    end
  end

  defp normalize_run_state(_value), do: nil

  defp scan_issue(source) do
    packet_status = source.metadata |> metadata_value("packet") |> metadata_value("status")
    summary = metadata_value(source.metadata, "last_scan_summary")
    diagnosis = metadata_value(summary, "diagnosis")
    extracted = metadata_integer(summary, "extracted")
    saved = metadata_integer(summary, "saved")

    cond do
      packet_status == "login_required" ->
        :login_required

      packet_status == "download_failed" ->
        :document_capture_failed

      diagnosis == "selector_failed" ->
        :selector_failed

      diagnosis in ["all_candidates_filtered_before_scoring", "no_candidates_extracted"] ->
        :no_results

      is_integer(extracted) and extracted == 0 ->
        :no_results

      is_integer(extracted) and extracted > 0 and saved in [0, nil] ->
        :zero_saved

      true ->
        nil
    end
  end

  defp scan_issue_note(source) do
    summary = metadata_value(source.metadata, "last_scan_summary") || %{}
    diagnosis = metadata_value(summary, "diagnosis")
    extracted = metadata_integer(summary, "extracted") || 0
    scored = metadata_integer(summary, "scored") || 0
    saved = metadata_integer(summary, "saved") || 0

    case scan_issue(source) do
      :login_required ->
        "Last scan found protected packet access. Load credentials and rescan."

      :document_capture_failed ->
        "Last scan found packet links but document capture failed. Check portal access or expired links."

      :selector_failed ->
        "Last scan could not read the configured selectors. Recheck source configuration."

      :no_results ->
        "Last scan produced no reviewable candidates. Extracted #{extracted}, scored #{scored}, saved #{saved}."

      :zero_saved ->
        "Last scan extracted #{extracted} and scored #{scored}, but saved 0. #{diagnosis_note(diagnosis)}"

      _ ->
        "Last scan needs operator review."
    end
  end

  defp diagnosis_note("scored_but_below_save_threshold"),
    do: "Top candidates were below save threshold."

  defp diagnosis_note("candidates_rejected_by_scoring"),
    do: "Top candidates were rejected by scoring."

  defp diagnosis_note(_diagnosis), do: "Review scan diagnostics."

  defp needs_login?(source) do
    source_type = metadata_value(source.metadata, "procurement_source_type")

    credentialed_source?(source.metadata, source_type) and
      not GnomeGarden.Procurement.SourceCredentials.credentials_configured?(source_type)
  end

  defp credentialed_source?(metadata, source_type) do
    metadata_value(metadata, "procurement_requires_login") in [true, "true"] or
      normalize_source_type(source_type) == :planetbids
  end

  defp missing_credentials_note(source) do
    source.metadata
    |> metadata_value("procurement_source_type")
    |> GnomeGarden.Procurement.SourceCredentials.missing_credentials_message()
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(metadata, key)
  end

  defp metadata_value(_metadata, _key), do: nil

  defp metadata_integer(metadata, key) do
    case metadata_value(metadata, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp normalize_source_type(value) when is_atom(value), do: value

  defp normalize_source_type(value) when is_binary(value) do
    case value do
      "planetbids" -> :planetbids
      _ -> nil
    end
  end

  defp normalize_source_type(_value), do: nil

  defp stale?(source, opts) do
    source.status in [:active, :candidate] and source.enabled != false and
      stale_reference_missing_or_old?(source, Keyword.fetch!(opts, :stale_after_hours))
  end

  defp stale_reference_missing_or_old?(source, stale_after_hours) do
    case source.last_success_at || source.last_run_at do
      nil ->
        true

      %DateTime{} = timestamp ->
        DateTime.diff(DateTime.utc_now(), timestamp, :hour) >= stale_after_hours

      _ ->
        true
    end
  end

  defp noisy?(source) do
    noise_count = source.noise_finding_count || 0
    productive_count = productive_finding_count(source)

    noise_count >= 3 and noise_count >= productive_count
  end

  defp productive_finding_count(source) do
    (source.review_finding_count || 0) + (source.promoted_finding_count || 0)
  end

  defp timestamp_note(prefix, %DateTime{} = timestamp) do
    "#{prefix} #{Calendar.strftime(timestamp, "%b %d, %Y %H:%M")}."
  end

  defp timestamp_note(prefix, _timestamp), do: "#{prefix}."
end
