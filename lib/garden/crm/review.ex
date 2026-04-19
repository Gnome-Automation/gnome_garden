defmodule GnomeGarden.CRM.Review do
  @moduledoc """
  Compatibility wrapper that routes older review flows into the commercial
  signal and pursuit model.
  """

  alias GnomeGarden.CRM.PipelineEvents
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.Pursuit
  alias GnomeGarden.Commercial.Signal
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  def accept_review_item(params, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, signal} <- resolve_signal(params, actor),
         original_status <- signal.status,
         {:ok, signal} <- ensure_signal_ready(signal, actor),
         {:ok, pursuit} <- ensure_pursuit(signal, params, actor),
         {:ok, signal} <- refresh_signal(signal, actor),
         :ok <- log_pursuit(params, signal, pursuit, original_status, actor) do
      {:ok, %{signal: signal, pursuit: pursuit}}
    end
  end

  defp resolve_signal(params, actor) do
    cond do
      bid_id = value(params, :bid_id) ->
        resolve_bid_signal(bid_id, actor)

      target_account_id = value(params, :target_account_id) ->
        resolve_target_account_signal(target_account_id, actor)

      true ->
        create_manual_signal(params, actor)
    end
  end

  defp resolve_bid_signal(bid_id, actor) do
    with {:ok, bid} <- Procurement.get_bid(bid_id, actor: actor, load: [:signal]) do
      case bid.signal do
        %Signal{} = signal -> {:ok, signal}
        nil -> Commercial.create_signal_from_bid(bid.id, actor: actor)
      end
    end
  end

  defp resolve_target_account_signal(target_account_id, actor) do
    with {:ok, target_account} <-
           Commercial.get_target_account(
             target_account_id,
             actor: actor,
             load: [:promoted_signal, :latest_observed_at, :latest_observation_summary]
           ) do
      cond do
        target_account.promoted_signal_id ->
          Commercial.get_signal(target_account.promoted_signal_id, actor: actor)

        target_account.status in [:new, :reviewing] ->
          with {:ok, promoted_target_account} <-
                 Commercial.promote_target_account_to_signal(target_account, actor: actor) do
            Commercial.get_signal(promoted_target_account.promoted_signal_id, actor: actor)
          end

        target_account.status in [:rejected, :archived] ->
          with {:ok, reopened_target_account} <-
                 Commercial.reopen_target_account(target_account, actor: actor),
               {:ok, promoted_target_account} <-
                 Commercial.promote_target_account_to_signal(reopened_target_account,
                   actor: actor
                 ) do
            Commercial.get_signal(promoted_target_account.promoted_signal_id, actor: actor)
          end
      end
    end
  end

  defp create_manual_signal(params, actor) do
    with {:ok, organization} <-
           ensure_organization(
             params,
             value(params, :company_name),
             value(params, :region),
             actor
           ) do
      Commercial.create_signal(
        %{
          title: signal_title(params, organization.name),
          description: value(params, :description),
          signal_type: signal_type_from_source(value(params, :source)),
          source_channel: source_channel_from_source(value(params, :source)),
          external_ref: manual_external_ref(params),
          source_url: value(params, :source_url),
          observed_at: DateTime.utc_now(),
          organization_id: organization.id,
          notes: value(params, :reason),
          metadata:
            reject_nil_values(%{
              lead_id: value(params, :lead_id),
              target_account_id: value(params, :target_account_id),
              bid_id: value(params, :bid_id),
              workflow: value(params, :workflow)
            })
        },
        actor: actor
      )
    end
  end

  defp ensure_signal_ready(%Signal{status: :accepted} = signal, _actor), do: {:ok, signal}
  defp ensure_signal_ready(%Signal{status: :converted} = signal, _actor), do: {:ok, signal}

  defp ensure_signal_ready(%Signal{status: status} = signal, actor)
       when status in [:new, :reviewing] do
    Commercial.accept_signal(signal, actor: actor)
  end

  defp ensure_signal_ready(%Signal{status: status} = signal, actor)
       when status in [:rejected, :archived] do
    with {:ok, reopened_signal} <- Commercial.reopen_signal(signal, actor: actor) do
      Commercial.accept_signal(reopened_signal, actor: actor)
    end
  end

  defp ensure_pursuit(%Signal{} = signal, params, actor) do
    with {:ok, loaded_signal} <- Commercial.get_signal(signal.id, actor: actor, load: [:pursuits]) do
      case loaded_signal.pursuits do
        [%Pursuit{} = pursuit | _rest] ->
          {:ok, pursuit}

        [] when loaded_signal.status == :accepted ->
          Commercial.create_pursuit_from_signal(
            loaded_signal.id,
            pursuit_attrs(params, loaded_signal),
            actor: actor
          )

        [] ->
          {:error, "signal must be accepted before creating a pursuit"}
      end
    end
  end

  defp refresh_signal(%Signal{} = signal, actor) do
    Commercial.get_signal(signal.id, actor: actor)
  end

  defp log_pursuit(params, signal, pursuit, original_status, actor) do
    case PipelineEvents.log(
           %{
             event_type: :pursued,
             subject_type: source_type_from(params),
             subject_id: source_id_from(params) || signal.id,
             summary: "Pursued — #{pursuit.name}",
             reason: value(params, :reason),
             from_state: to_string(original_status),
             to_state: to_string(pursuit.stage),
             actor_id: actor && actor.id,
             metadata: %{
               signal_id: signal.id,
               pursuit_id: pursuit.id,
               organization_id: pursuit.organization_id,
               signal_status: signal.status,
               pursuit_type: pursuit.pursuit_type
             }
           },
           actor: actor
         ) do
      {:ok, _event} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp ensure_organization(_params, nil, _region, _actor),
    do: {:error, "company_name is required to create a pursuit"}

  defp ensure_organization(params, name, region, _actor) do
    Operations.create_organization(
      %{
        name: name,
        status: :prospect,
        relationship_roles: organization_roles(value(params, :source)),
        website: value(params, :website),
        primary_region: normalize_region(region),
        notes: value(params, :description)
      },
      upsert?: true,
      upsert_identity: :unique_name,
      upsert_fields: [:website, :primary_region, :notes, :relationship_roles]
    )
  end

  defp pursuit_attrs(params, signal) do
    %{
      organization_id: signal.organization_id,
      name: value(params, :opportunity_name) || signal.title,
      description: value(params, :description) || signal.description,
      pursuit_type: pursuit_type_from_signal(signal),
      priority: priority_from_signal(signal),
      target_value: value(params, :amount),
      expected_close_on: parse_date(value(params, :expected_close_date)),
      notes: value(params, :reason)
    }
    |> reject_nil_values()
  end

  defp pursuit_type_from_signal(%Signal{signal_type: :bid_notice}), do: :bid_response
  defp pursuit_type_from_signal(%Signal{signal_type: :outbound_target}), do: :new_logo
  defp pursuit_type_from_signal(%Signal{signal_type: :referral}), do: :new_logo
  defp pursuit_type_from_signal(%Signal{signal_type: :inbound_request}), do: :existing_account
  defp pursuit_type_from_signal(%Signal{signal_type: :renewal}), do: :renewal
  defp pursuit_type_from_signal(%Signal{signal_type: :service_need}), do: :service_expansion
  defp pursuit_type_from_signal(_signal), do: :other

  defp priority_from_signal(%Signal{signal_type: :bid_notice}), do: :high
  defp priority_from_signal(%Signal{signal_type: :renewal}), do: :high
  defp priority_from_signal(%Signal{signal_type: :service_need}), do: :high
  defp priority_from_signal(_signal), do: :normal

  defp signal_title(params, fallback_name) do
    value(params, :opportunity_name) || value(params, :title) || fallback_name
  end

  defp signal_type_from_source(:bid), do: :bid_notice
  defp signal_type_from_source(:target_account), do: :outbound_target
  defp signal_type_from_source(:outbound), do: :outbound_target
  defp signal_type_from_source(:referral), do: :referral
  defp signal_type_from_source(:renewal), do: :renewal
  defp signal_type_from_source(:service), do: :service_need
  defp signal_type_from_source(:inbound), do: :inbound_request
  defp signal_type_from_source(_), do: :other

  defp source_channel_from_source(:bid), do: :procurement_portal
  defp source_channel_from_source(:target_account), do: :agent_discovery
  defp source_channel_from_source(:outbound), do: :agent_discovery
  defp source_channel_from_source(:referral), do: :referral
  defp source_channel_from_source(:inbound), do: :website
  defp source_channel_from_source(_), do: :manual

  defp organization_roles(:bid), do: ["prospect", "agency"]
  defp organization_roles(:target_account), do: ["prospect"]
  defp organization_roles(:outbound), do: ["prospect"]
  defp organization_roles(:referral), do: ["prospect"]
  defp organization_roles(:renewal), do: ["customer"]
  defp organization_roles(:service), do: ["customer"]
  defp organization_roles(:inbound), do: ["prospect"]
  defp organization_roles(_), do: ["prospect"]

  defp source_type_from(params) do
    cond do
      value(params, :bid_id) -> "bid"
      value(params, :target_account_id) -> "target_account"
      value(params, :lead_id) -> "lead"
      true -> "signal"
    end
  end

  defp source_id_from(params) do
    value(params, :bid_id) ||
      value(params, :target_account_id) ||
      value(params, :lead_id)
  end

  defp manual_external_ref(params) do
    cond do
      lead_id = value(params, :lead_id) -> "legacy-lead:#{lead_id}"
      title = value(params, :title) -> "manual:#{title}"
      true -> nil
    end
  end

  defp normalize_region(nil), do: nil
  defp normalize_region(region) when is_atom(region), do: to_string(region)
  defp normalize_region(region), do: region

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp reject_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp value(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end
end
