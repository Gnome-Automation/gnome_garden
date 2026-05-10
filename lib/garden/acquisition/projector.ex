defmodule GnomeGarden.Acquisition.Projector do
  @moduledoc false

  require Logger

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryProgram
  alias GnomeGarden.Commercial.DiscoveryRecord
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.Bid
  alias GnomeGarden.Procurement.ProcurementSource

  @finding_upsert_fields [
    :title,
    :summary,
    :source_url,
    :finding_family,
    :finding_type,
    :status,
    :due_at,
    :due_note,
    :location,
    :location_note,
    :work_summary,
    :work_type,
    :work_note,
    :fit_score,
    :score_tier,
    :score_note,
    :intent_score,
    :confidence,
    :recommendation,
    :watchouts,
    :observed_at,
    :reviewed_at,
    :promoted_at,
    :metadata,
    :source_id,
    :program_id,
    :organization_id,
    :signal_id,
    :source_bid_id,
    :source_discovery_record_id
  ]

  @source_upsert_fields [
    :name,
    :url,
    :status,
    :enabled,
    :scan_strategy,
    :description,
    :metadata,
    :last_run_at,
    :last_success_at,
    :procurement_source_id,
    :organization_id
  ]

  @program_upsert_fields [
    :name,
    :description,
    :status,
    :scope,
    :metadata,
    :last_run_at,
    :discovery_program_id,
    :owner_user_id
  ]

  def sync_bid(%Bid{id: bid_id}, opts) when is_binary(bid_id),
    do: load_bid_and_sync(bid_id, Keyword.get(opts, :actor))

  def sync_bid(%Bid{} = bid, opts), do: do_sync_bid(bid, Keyword.get(opts, :actor))

  def sync_bid(bid_id, opts) when is_binary(bid_id),
    do: load_bid_and_sync(bid_id, Keyword.get(opts, :actor))

  def sync_discovery_record(%DiscoveryRecord{id: discovery_record_id}, opts)
      when is_binary(discovery_record_id),
      do: load_discovery_record_and_sync(discovery_record_id, Keyword.get(opts, :actor))

  def sync_discovery_record(%DiscoveryRecord{} = discovery_record, opts),
    do: do_sync_discovery_record(discovery_record, Keyword.get(opts, :actor))

  def sync_discovery_record(discovery_record_id, opts) when is_binary(discovery_record_id),
    do: load_discovery_record_and_sync(discovery_record_id, Keyword.get(opts, :actor))

  def sync_source(%ProcurementSource{id: source_id}, opts) when is_binary(source_id),
    do: load_source_and_sync(source_id, Keyword.get(opts, :actor))

  def sync_source(%ProcurementSource{} = source, opts),
    do: do_sync_source(source, Keyword.get(opts, :actor))

  def sync_source(source_id, opts) when is_binary(source_id),
    do: load_source_and_sync(source_id, Keyword.get(opts, :actor))

  def sync_program(%DiscoveryProgram{id: program_id}, opts) when is_binary(program_id),
    do: load_program_and_sync(program_id, Keyword.get(opts, :actor))

  def sync_program(%DiscoveryProgram{} = discovery_program, opts),
    do: do_sync_program(discovery_program, Keyword.get(opts, :actor))

  def sync_program(program_id, opts) when is_binary(program_id),
    do: load_program_and_sync(program_id, Keyword.get(opts, :actor))

  def backfill(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    procurement_source_count =
      Procurement.list_procurement_sources(actor: actor)
      |> case do
        {:ok, sources} ->
          Enum.each(sources, &sync_source(&1, actor: actor))
          length(sources)

        {:error, error} ->
          Logger.warning(
            "Failed to backfill procurement sources into acquisition sources: #{inspect(error)}"
          )

          0
      end

    procurement_count =
      Procurement.list_bids(actor: actor)
      |> case do
        {:ok, bids} ->
          Enum.each(bids, &sync_bid(&1, actor: actor))
          length(bids)

        {:error, error} ->
          Logger.warning(
            "Failed to backfill procurement bids into acquisition findings: #{inspect(error)}"
          )

          0
      end

    discovery_program_count =
      Commercial.list_discovery_programs(actor: actor)
      |> case do
        {:ok, discovery_programs} ->
          Enum.each(discovery_programs, &sync_program(&1, actor: actor))
          length(discovery_programs)

        {:error, error} ->
          Logger.warning(
            "Failed to backfill discovery programs into acquisition programs: #{inspect(error)}"
          )

          0
      end

    discovery_count =
      Commercial.list_discovery_records(actor: actor)
      |> case do
        {:ok, discovery_records} ->
          Enum.each(discovery_records, &sync_discovery_record(&1, actor: actor))
          length(discovery_records)

        {:error, error} ->
          Logger.warning(
            "Failed to backfill discovery records into acquisition findings: #{inspect(error)}"
          )

          0
      end

    {:ok,
     %{
       procurement_source_count: procurement_source_count,
       procurement_count: procurement_count,
       discovery_program_count: discovery_program_count,
       discovery_count: discovery_count
     }}
  end

  defp load_bid_and_sync(bid_id, actor) do
    bid_id
    |> Procurement.get_bid(
      actor: actor,
      load: [:signal, :organization, :procurement_source]
    )
    |> case do
      {:ok, bid} -> do_sync_bid(bid, actor)
      {:error, error} -> {:error, error}
    end
  end

  defp load_source_and_sync(source_id, actor) do
    source_id
    |> Procurement.get_procurement_source(actor: actor)
    |> case do
      {:ok, source} -> do_sync_source(source, actor)
      {:error, error} -> {:error, error}
    end
  end

  defp do_sync_source(%ProcurementSource{} = source, actor) do
    source
    |> maybe_ensure_source(actor)
    |> case do
      nil -> {:error, :source_sync_failed}
      source_id -> Acquisition.get_source(source_id, actor: actor)
    end
  end

  defp do_sync_bid(%Bid{} = bid, actor) do
    source_id =
      bid
      |> procurement_source_for_bid(actor)
      |> maybe_ensure_source(actor)

    existing_finding = existing_finding_for_bid(bid.id, actor)

    Acquisition.create_finding(
      bid_finding_attrs(bid, source_id, existing_finding),
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_external_ref,
      upsert_fields: @finding_upsert_fields
    )
  end

  defp load_discovery_record_and_sync(discovery_record_id, actor) do
    discovery_record_id
    |> Commercial.get_discovery_record(
      actor: actor,
      load: [
        :organization,
        :promoted_signal,
        :latest_evidence_at,
        :latest_evidence_summary,
        :discovery_program
      ]
    )
    |> case do
      {:ok, discovery_record} -> do_sync_discovery_record(discovery_record, actor)
      {:error, error} -> {:error, error}
    end
  end

  defp load_program_and_sync(program_id, actor) do
    program_id
    |> Commercial.get_discovery_program(actor: actor)
    |> case do
      {:ok, discovery_program} -> do_sync_program(discovery_program, actor)
      {:error, error} -> {:error, error}
    end
  end

  defp do_sync_program(%DiscoveryProgram{} = discovery_program, actor) do
    discovery_program
    |> maybe_ensure_program(actor)
    |> case do
      nil -> {:error, :program_sync_failed}
      acquisition_program_id -> Acquisition.get_program(acquisition_program_id, actor: actor)
    end
  end

  defp do_sync_discovery_record(%DiscoveryRecord{} = discovery_record, actor) do
    program_id =
      discovery_record
      |> discovery_program_for_discovery_record(actor)
      |> maybe_ensure_program(actor)

    existing_finding = existing_finding_for_discovery_record(discovery_record.id, actor)

    Acquisition.create_finding(
      discovery_record_finding_attrs(discovery_record, program_id, existing_finding),
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_source_discovery_record,
      upsert_fields: @finding_upsert_fields
    )
  end

  defp maybe_ensure_source(nil, _actor), do: nil
  defp maybe_ensure_source(%Ash.NotLoaded{}, _actor), do: nil

  defp maybe_ensure_source(%ProcurementSource{} = source, actor) do
    metadata =
      source.metadata
      |> Map.new()
      |> Map.put("procurement_status", source.status)
      |> Map.put("procurement_config_status", source.config_status)
      |> Map.put("procurement_source_type", source.source_type)
      |> Map.put("portal_id", source.portal_id)

    Acquisition.create_source(
      %{
        external_ref: "procurement_source:#{source.id}",
        name: source.name,
        url: source.url,
        source_family: :procurement,
        source_kind: acquisition_source_kind(source.source_type),
        status: acquisition_source_status(source),
        enabled: source.enabled,
        scan_strategy: acquisition_scan_strategy(source),
        description: source.notes,
        metadata: metadata,
        last_run_at: source.last_scanned_at,
        last_success_at: source.last_scanned_at,
        procurement_source_id: source.id,
        organization_id: source.organization_id
      },
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_external_ref,
      upsert_fields: @source_upsert_fields
    )
    |> case do
      {:ok, acquisition_source} ->
        acquisition_source.id

      {:error, error} ->
        Logger.warning(
          "Failed to upsert acquisition source for procurement source #{source.id}: #{inspect(error)}"
        )

        nil
    end
  end

  defp maybe_ensure_program(nil, _actor), do: nil
  defp maybe_ensure_program(%Ash.NotLoaded{}, _actor), do: nil

  defp maybe_ensure_program(discovery_program, actor) do
    Acquisition.create_program(
      %{
        external_ref: "discovery_program:#{discovery_program.id}",
        name: discovery_program.name,
        description: discovery_program.description,
        program_family: :discovery,
        program_type: :discovery_run,
        status: acquisition_program_status(discovery_program.status),
        scope: %{
          target_regions: discovery_program.target_regions,
          target_industries: discovery_program.target_industries,
          search_terms: discovery_program.search_terms,
          watch_channels: discovery_program.watch_channels,
          cadence_hours: discovery_program.cadence_hours
        },
        metadata: %{
          discovery_program_status: discovery_program.status,
          last_run_metadata: discovery_program.metadata
        },
        last_run_at: discovery_program.last_run_at,
        discovery_program_id: discovery_program.id,
        owner_user_id: discovery_program.owner_user_id
      },
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_external_ref,
      upsert_fields: @program_upsert_fields
    )
    |> case do
      {:ok, program} ->
        program.id

      {:error, error} ->
        Logger.warning(
          "Failed to upsert acquisition program for discovery program #{discovery_program.id}: #{inspect(error)}"
        )

        nil
    end
  end

  defp bid_finding_attrs(%Bid{} = bid, source_id, existing_finding) do
    %{
      external_ref: "procurement_bid:#{bid.id}",
      title: bid.title,
      summary: bid.description || bid.score_recommendation,
      source_url: bid.url,
      finding_family: :procurement,
      finding_type: :bid_notice,
      status: preserved_acquisition_status(bid_finding_status(bid), existing_finding),
      due_at: bid.due_at,
      due_note: bid_due_note(bid),
      location: bid.location,
      location_note: humanize_optional_token(bid.region),
      work_summary: bid_work_summary(bid),
      work_type: humanize_optional_token(bid.bid_type) || "Bid notice",
      work_note: bid.agency || first_watchout(bid.score_risk_flags),
      fit_score: bid.score_total,
      score_tier: bid.score_tier || derive_score_tier(bid.score_total),
      score_note: procurement_score_note(bid),
      intent_score: nil,
      confidence: bid_confidence(bid.score_source_confidence),
      recommendation: bid.score_recommendation,
      watchouts: bid.score_risk_flags || [],
      observed_at: bid.posted_at || bid.discovered_at || bid.inserted_at,
      reviewed_at:
        if(bid.status in [:reviewing, :rejected, :parked], do: bid.updated_at, else: nil),
      promoted_at: if(not is_nil(bid.signal_id), do: bid.updated_at, else: nil),
      metadata:
        reject_nil_values(%{
          bid_status: bid.status,
          procurement_source_id: bid.procurement_source_id,
          external_id: bid.external_id,
          agency: bid.agency,
          location: bid.location,
          region: bid.region,
          due_at: bid.due_at,
          estimated_value: bid.estimated_value,
          keywords_matched: bid.keywords_matched,
          keywords_rejected: bid.keywords_rejected,
          score_icp_matches: bid.score_icp_matches,
          score_risk_flags: bid.score_risk_flags,
          score_tier: bid.score_tier,
          score_company_profile_key: bid.score_company_profile_key,
          score_company_profile_mode: bid.score_company_profile_mode,
          score_recommendation: bid.score_recommendation,
          score_total: bid.score_total,
          score_source_confidence: bid.score_source_confidence
        }),
      source_id: source_id,
      organization_id: bid.organization_id,
      signal_id: bid.signal_id,
      source_bid_id: bid.id
    }
  end

  defp discovery_record_finding_attrs(
         %DiscoveryRecord{} = discovery_record,
         program_id,
         existing_finding
       ) do
    market_focus = metadata_value(discovery_record.metadata, "market_focus")

    %{
      external_ref: "discovery_record:#{discovery_record.id}",
      title: discovery_record.name,
      summary: loaded_value(discovery_record.latest_evidence_summary) || discovery_record.notes,
      source_url: discovery_record.website,
      finding_family: :discovery,
      finding_type: discovery_finding_type(discovery_record),
      status:
        preserved_acquisition_status(
          discovery_record_finding_status(discovery_record),
          existing_finding
        ),
      due_at: nil,
      due_note: nil,
      location: discovery_record.location,
      location_note: blank_to_nil(discovery_record.region),
      work_summary: discovery_work_summary(discovery_record),
      work_type: humanize_optional_token(discovery_record.size_bucket),
      work_note: nil,
      fit_score: discovery_record.fit_score,
      score_tier: derive_score_tier(discovery_record.fit_score),
      score_note: discovery_score_note(discovery_record),
      intent_score: discovery_record.intent_score,
      confidence: discovery_record_confidence(discovery_record),
      recommendation: discovery_recommendation(discovery_record),
      watchouts: metadata_value(market_focus, "risk_flags") |> List.wrap(),
      observed_at:
        loaded_value(discovery_record.latest_evidence_at) || discovery_record.inserted_at,
      reviewed_at:
        if(discovery_record.status in [:reviewing, :rejected, :archived],
          do: discovery_record.updated_at,
          else: nil
        ),
      promoted_at:
        if(not is_nil(discovery_record.promoted_signal_id),
          do: discovery_record.promoted_at,
          else: nil
        ),
      metadata:
        reject_nil_values(%{
          target_status: discovery_record.status,
          discovery_feedback: metadata_value(discovery_record.metadata, "discovery_feedback"),
          market_focus: market_focus,
          website_domain: discovery_record.website_domain,
          size_bucket: discovery_record.size_bucket,
          discovery_program_id: discovery_record.discovery_program_id
        }),
      program_id: program_id,
      organization_id: discovery_record.organization_id,
      signal_id: discovery_record.promoted_signal_id,
      source_discovery_record_id: discovery_record.id
    }
  end

  defp acquisition_source_kind(source_type) when source_type == :company_site, do: :company_site
  defp acquisition_source_kind(source_type) when source_type in [:directory], do: :directory
  defp acquisition_source_kind(source_type) when source_type in [:job_board], do: :job_board
  defp acquisition_source_kind(_source_type), do: :portal

  defp acquisition_source_status(%{enabled: false}), do: :paused
  defp acquisition_source_status(%{status: :blocked}), do: :blocked
  defp acquisition_source_status(%{status: :ignored}), do: :archived
  defp acquisition_source_status(%{status: :candidate}), do: :candidate
  defp acquisition_source_status(_source), do: :active

  defp acquisition_scan_strategy(%{source_type: source_type}) do
    case ProcurementSource.scanner_strategy(source_type) do
      :deterministic -> :deterministic
      :company -> :agentic
      _ -> :agentic
    end
  end

  defp acquisition_program_status(:active), do: :active
  defp acquisition_program_status(:archived), do: :archived
  defp acquisition_program_status(_), do: :paused

  defp preserved_acquisition_status(projected_status, %{status: :accepted})
       when projected_status in [:new, :reviewing],
       do: :accepted

  defp preserved_acquisition_status(projected_status, %{status: :suppressed})
       when projected_status in [:new, :reviewing, :rejected],
       do: :suppressed

  defp preserved_acquisition_status(projected_status, %{status: :parked})
       when projected_status in [:new, :reviewing, :rejected],
       do: :parked

  defp preserved_acquisition_status(projected_status, _existing_finding), do: projected_status

  defp bid_finding_status(%{signal_id: signal_id}) when is_binary(signal_id), do: :promoted
  defp bid_finding_status(%{status: :reviewing}), do: :reviewing
  defp bid_finding_status(%{status: :parked}), do: :parked

  defp bid_finding_status(%{status: :rejected} = bid) do
    if bid_noise_feedback?(bid), do: :suppressed, else: :rejected
  end

  defp bid_finding_status(%{status: status})
       when status in [:pursuing, :submitted, :won, :lost, :expired], do: :promoted

  defp bid_finding_status(_bid), do: :new

  defp discovery_record_finding_status(%{promoted_signal_id: signal_id})
       when is_binary(signal_id),
       do: :promoted

  defp discovery_record_finding_status(%{status: :reviewing}), do: :reviewing

  defp discovery_record_finding_status(%{status: :rejected} = discovery_record) do
    cond do
      discovery_record_noise_feedback?(discovery_record) -> :suppressed
      discovery_record_parked_feedback?(discovery_record) -> :parked
      true -> :rejected
    end
  end

  defp discovery_record_finding_status(%{status: :archived}), do: :suppressed
  defp discovery_record_finding_status(_discovery_record), do: :new

  defp bid_confidence(:direct), do: :high
  defp bid_confidence(:aggregated), do: :medium
  defp bid_confidence(:unknown), do: :low
  defp bid_confidence(_), do: :medium

  defp discovery_record_confidence(%{intent_score: intent_score})
       when is_integer(intent_score) and intent_score >= 80,
       do: :high

  defp discovery_record_confidence(%{fit_score: fit_score})
       when is_integer(fit_score) and fit_score >= 70,
       do: :medium

  defp discovery_record_confidence(_discovery_record), do: :low

  defp discovery_finding_type(%{record_type: :opportunity}), do: :integrator_request

  defp discovery_finding_type(discovery_record) do
    discovery_record.metadata
    |> metadata_value("market_focus")
    |> metadata_value("source_category")
    |> case do
      "hiring" ->
        :hiring_signal

      "expansion" ->
        :expansion_signal

      "contact" ->
        :contact_signal

      _ ->
        infer_discovery_finding_type_from_text(
          loaded_value(discovery_record.latest_evidence_summary) || discovery_record.notes
        )
    end
  end

  defp infer_discovery_finding_type_from_text(nil), do: :company_signal

  defp infer_discovery_finding_type_from_text(text) when is_binary(text) do
    text = String.downcase(text)

    cond do
      String.contains?(text, ["hiring", "job", "career"]) ->
        :hiring_signal

      String.contains?(text, ["expansion", "new line", "modernization", "new facility"]) ->
        :expansion_signal

      String.contains?(text, ["contact", "intake form", "referral"]) ->
        :contact_signal

      true ->
        :company_signal
    end
  end

  defp discovery_recommendation(%{promoted_signal_id: signal_id}) when is_binary(signal_id),
    do: "Review signal"

  defp discovery_recommendation(%{fit_score: fit_score, intent_score: intent_score})
       when is_integer(fit_score) and is_integer(intent_score) and fit_score >= 75 and
              intent_score >= 80,
       do: "Promote to signal"

  defp discovery_recommendation(%{intent_score: intent_score})
       when is_integer(intent_score) and intent_score >= 65,
       do: "Start review"

  defp discovery_recommendation(_discovery_record), do: "Reject and teach"

  defp bid_due_note(%{due_at: %DateTime{}}), do: "Procurement deadline"
  defp bid_due_note(_bid), do: nil

  defp bid_work_summary(%{score_icp_matches: [match | _]}) when is_binary(match),
    do: humanize_token(match)

  defp bid_work_summary(_bid), do: "Bid notice"

  defp procurement_score_note(%{score_source_confidence: confidence})
       when confidence in [:direct, :aggregated, :unknown] do
    confidence
    |> Atom.to_string()
    |> String.capitalize()
    |> Kernel.<>(" confidence")
  end

  defp procurement_score_note(_bid), do: nil

  defp discovery_work_summary(%{industry: industry}) when is_binary(industry) and industry != "",
    do: industry

  defp discovery_work_summary(discovery_record) do
    discovery_record
    |> discovery_finding_type()
    |> Atom.to_string()
    |> humanize_token()
  end

  defp discovery_score_note(%{intent_score: intent_score}) when is_integer(intent_score),
    do: "Intent #{intent_score}"

  defp discovery_score_note(_discovery_record), do: nil

  defp derive_score_tier(score) when is_integer(score) and score >= 75, do: :hot
  defp derive_score_tier(score) when is_integer(score) and score >= 50, do: :warm
  defp derive_score_tier(score) when is_integer(score), do: :prospect
  defp derive_score_tier(_score), do: nil

  defp procurement_source_for_bid(%{procurement_source: %ProcurementSource{} = source}, _actor),
    do: source

  defp procurement_source_for_bid(
         %{procurement_source: %Ash.NotLoaded{}, procurement_source_id: nil},
         _actor
       ),
       do: nil

  defp procurement_source_for_bid(
         %{procurement_source: %Ash.NotLoaded{}, procurement_source_id: source_id},
         actor
       )
       when is_binary(source_id) do
    case Procurement.get_procurement_source(source_id, actor: actor) do
      {:ok, source} -> source
      _ -> nil
    end
  end

  defp procurement_source_for_bid(%{procurement_source_id: source_id}, actor)
       when is_binary(source_id) do
    case Procurement.get_procurement_source(source_id, actor: actor) do
      {:ok, source} -> source
      _ -> nil
    end
  end

  defp procurement_source_for_bid(_bid, _actor), do: nil

  defp discovery_program_for_discovery_record(
         %{discovery_program: %GnomeGarden.Commercial.DiscoveryProgram{} = discovery_program},
         _actor
       ),
       do: discovery_program

  defp discovery_program_for_discovery_record(
         %{discovery_program: %Ash.NotLoaded{}, discovery_program_id: nil},
         _actor
       ),
       do: nil

  defp discovery_program_for_discovery_record(
         %{discovery_program: %Ash.NotLoaded{}, discovery_program_id: discovery_program_id},
         actor
       )
       when is_binary(discovery_program_id) do
    case Commercial.get_discovery_program(discovery_program_id, actor: actor) do
      {:ok, discovery_program} -> discovery_program
      _ -> nil
    end
  end

  defp discovery_program_for_discovery_record(
         %{discovery_program_id: discovery_program_id},
         actor
       )
       when is_binary(discovery_program_id) do
    case Commercial.get_discovery_program(discovery_program_id, actor: actor) do
      {:ok, discovery_program} -> discovery_program
      _ -> nil
    end
  end

  defp discovery_program_for_discovery_record(_discovery_record, _actor), do: nil

  defp bid_noise_feedback?(bid) do
    bid
    |> metadata_value("targeting_feedback")
    |> metadata_value("source_feedback_category")
    |> Kernel.in(["noisy_source", "duplicate_intake"])
  end

  defp discovery_record_noise_feedback?(discovery_record) do
    discovery_record
    |> metadata_value("discovery_feedback")
    |> metadata_value("source_feedback_category")
    |> Kernel.==("source_noise")
  end

  defp discovery_record_parked_feedback?(discovery_record) do
    discovery_record
    |> metadata_value("discovery_feedback")
    |> metadata_value("reason_code")
    |> Kernel.==("not_ready_yet")
  end

  defp existing_finding_for_bid(bid_id, actor) do
    case Acquisition.get_finding_by_source_bid(bid_id, actor: actor) do
      {:ok, finding} -> finding
      _ -> nil
    end
  end

  defp existing_finding_for_discovery_record(discovery_record_id, actor) do
    case Acquisition.get_finding_by_source_discovery_record(discovery_record_id, actor: actor) do
      {:ok, finding} -> finding
      _ -> nil
    end
  end

  defp loaded_value(%Ash.NotLoaded{}), do: nil
  defp loaded_value(value), do: value

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp first_watchout([watchout | _]) when is_binary(watchout), do: "Watchout: #{watchout}"
  defp first_watchout(_watchouts), do: nil

  defp humanize_optional_token(nil), do: nil
  defp humanize_optional_token(value), do: value |> to_string() |> humanize_token()

  defp humanize_token(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    map = if is_struct(map), do: Map.from_struct(map), else: map

    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      is_atom(key) and Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      is_binary(key) ->
        Enum.find_value(map, fn
          {map_key, value} when is_atom(map_key) ->
            if Atom.to_string(map_key) == key, do: value

          _ ->
            nil
        end)

      true ->
        nil
    end
  end

  defp metadata_value(_value, _key), do: nil

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
