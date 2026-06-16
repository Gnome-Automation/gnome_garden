defmodule GnomeGarden.Finance.Actions.SyncBankConnection do
  @moduledoc """
  Pulls banking data from a provider and reconciles it into Finance resources.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.BankRules
  alias GnomeGarden.Finance.Integrations
  alias GnomeGarden.Finance.Integrations.Mercury, as: MercuryNormalizer

  @impl true
  def run(input, _opts, context) do
    source = Ash.ActionInput.get_argument(input, :source) || :manual_sync

    with {:ok, connection} <- resolve_connection(input, context.actor),
         {:ok, result} <- sync_connection(connection, source, context.actor) do
      {:ok, result}
    end
  rescue
    error ->
      {:error, error}
  end

  defp resolve_connection(input, actor) do
    case Ash.ActionInput.get_argument(input, :bank_connection_id) do
      nil ->
        provider = Ash.ActionInput.get_argument(input, :provider) || :mercury
        environment = Ash.ActionInput.get_argument(input, :environment) || :production
        ensure_connection(provider, environment, actor)

      id ->
        Finance.get_bank_connection(id, actor: actor, authorize?: false)
    end
  end

  defp ensure_connection(provider, environment, actor) do
    case Finance.get_bank_connection_by_provider_environment(provider, environment,
           actor: actor,
           authorize?: false
         ) do
      {:ok, connection} ->
        {:ok, connection}

      {:error, error} ->
        if not_found_error?(error) do
          Finance.create_bank_connection(
            %{
              provider: provider,
              environment: environment,
              name: default_connection_name(provider, environment),
              status: :active
            },
            actor: actor,
            authorize?: false
          )
        else
          {:error, error}
        end
    end
  end

  defp sync_connection(connection, source, actor) do
    {:ok, run} =
      Finance.start_bank_sync_run(
        %{
          bank_connection_id: connection.id,
          source: source
        },
        actor: actor,
        authorize?: false
      )

    {:ok, event} =
      Finance.record_bank_integration_event(
        %{
          bank_connection_id: connection.id,
          provider: connection.provider,
          event_type: "sync.started",
          source: source,
          payload: %{"bank_connection_id" => connection.id}
        },
        actor: actor,
        authorize?: false
      )

    case do_sync(connection, source, actor) do
      {:ok, result} ->
        {:ok, _run} =
          Finance.finish_bank_sync_run_success(
            run,
            %{
              accounts_seen_count: result.accounts_seen_count,
              transactions_seen_count: result.transactions_seen_count,
              transactions_created_count: result.transactions_created_count,
              transactions_updated_count: result.transactions_updated_count
            },
            actor: actor,
            authorize?: false
          )

        {:ok, _connection} =
          Finance.mark_bank_connection_sync_succeeded(connection, %{},
            actor: actor,
            authorize?: false
          )

        {:ok, _event} =
          Finance.mark_bank_integration_event_processed(event, actor: actor, authorize?: false)

        {:ok, result}

      {:error, reason} ->
        message = inspect(reason)

        {:ok, _run} =
          Finance.finish_bank_sync_run_failure(run, %{error_message: message},
            actor: actor,
            authorize?: false
          )

        {:ok, _connection} =
          Finance.mark_bank_connection_sync_failed(connection, %{last_error_message: message},
            actor: actor,
            authorize?: false
          )

        {:ok, _event} =
          Finance.mark_bank_integration_event_failed(event, %{error_message: message},
            actor: actor,
            authorize?: false
          )

        {:error, reason}
    end
  end

  defp do_sync(connection, source, actor) do
    adapter = Integrations.adapter(connection.provider)

    with {:ok, raw_accounts} <- adapter.list_accounts(provider_opts(connection)),
         {:ok, accounts} <- upsert_accounts(connection, raw_accounts, actor) do
      rules = Finance.list_bank_rules!(actor: actor, authorize?: false)

      account_results =
        Enum.map(accounts, fn account ->
          sync_account_transactions(adapter, account, rules, source, actor)
        end)

      case Enum.find(account_results, &match?({:error, _}, &1)) do
        nil ->
          totals =
            Enum.reduce(account_results, empty_result(length(raw_accounts)), fn {:ok, result},
                                                                                acc ->
              %{
                acc
                | transactions_seen_count:
                    acc.transactions_seen_count + result.transactions_seen_count,
                  transactions_created_count:
                    acc.transactions_created_count + result.transactions_created_count,
                  transactions_updated_count:
                    acc.transactions_updated_count + result.transactions_updated_count
              }
            end)

          {:ok, totals}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp upsert_accounts(connection, raw_accounts, actor) do
    raw_accounts
    |> Enum.map(&upsert_account(connection, &1, actor))
    |> collect_results()
  end

  defp upsert_account(connection, raw, actor) do
    attrs =
      MercuryNormalizer.account_attrs(raw,
        provider: connection.provider,
        bank_connection_id: connection.id
      )

    case Finance.get_bank_account_by_provider_id(
           attrs.provider,
           attrs.provider_account_id,
           actor: actor,
           authorize?: false
         ) do
      {:ok, account} ->
        attrs =
          attrs
          |> Map.drop([:provider, :provider_account_id, :bank_connection_id])

        Finance.update_bank_account(account, attrs, actor: actor, authorize?: false)

      {:error, error} ->
        if not_found_error?(error) do
          Finance.create_bank_account(attrs, actor: actor, authorize?: false)
        else
          {:error, error}
        end
    end
  end

  defp sync_account_transactions(adapter, account, rules, source, actor) do
    start_date = Date.utc_today() |> Date.add(-90) |> Date.to_iso8601()

    with {:ok, raw_transactions} <-
           adapter.list_transactions(account.provider_account_id, start_date: start_date) do
      result =
        Enum.reduce(raw_transactions, empty_account_result(), fn raw, acc ->
          case upsert_transaction(account, raw, rules, source, actor) do
            {:ok, :created} ->
              %{acc | transactions_created_count: acc.transactions_created_count + 1}

            {:ok, :updated} ->
              %{acc | transactions_updated_count: acc.transactions_updated_count + 1}

            {:error, reason} ->
              %{acc | errors: [reason | acc.errors]}
          end
        end)

      if result.errors == [] do
        {:ok, %{result | transactions_seen_count: length(raw_transactions)}}
      else
        {:error, result.errors}
      end
    end
  end

  defp upsert_transaction(account, raw, rules, source, actor) do
    attrs =
      MercuryNormalizer.transaction_attrs(raw,
        provider: account.provider,
        bank_account_id: account.id
      )

    case Finance.get_bank_transaction_by_provider_id(
           attrs.provider,
           attrs.provider_transaction_id,
           actor: actor,
           authorize?: false
         ) do
      {:ok, transaction} ->
        attrs = Map.drop(attrs, [:provider, :provider_transaction_id, :bank_account_id])

        with {:ok, transaction} <-
               Finance.update_bank_transaction(transaction, attrs,
                 actor: actor,
                 authorize?: false
               ),
             {:ok, _event} <- record_transaction_event(transaction, :updated, source, actor) do
          {:ok, :updated}
        end

      {:error, error} ->
        if not_found_error?(error) do
          with {:ok, transaction} <-
                 Finance.create_bank_transaction(attrs, actor: actor, authorize?: false),
               {:ok, _event} <- record_transaction_event(transaction, :imported, source, actor),
               {:ok, _transaction} <- maybe_apply_rule(transaction, rules, actor) do
            {:ok, :created}
          end
        else
          {:error, error}
        end
    end
  end

  defp maybe_apply_rule(transaction, rules, actor) do
    case BankRules.match(transaction, rules) do
      nil ->
        {:ok, transaction}

      rule ->
        match_status =
          case rule.match_behavior do
            :suggest -> :suggested
            :auto_accept_when_exact -> :suggested
            _ -> transaction.match_status
          end

        with {:ok, updated} <-
               Finance.apply_bank_rule_to_transaction(
                 transaction,
                 %{
                   category: rule.category,
                   reconciliation_note: rule.auto_note,
                   review_status: rule.review_status_result,
                   match_status: match_status
                 },
                 actor: actor,
                 authorize?: false
               ),
             {:ok, _event} <-
               Finance.record_bank_transaction_event(
                 %{
                   bank_transaction_id: updated.id,
                   event_type: :rule_applied,
                   source: :rule,
                   message: "Applied bank rule #{rule.name}",
                   metadata: %{"bank_rule_id" => rule.id}
                 },
                 actor: actor,
                 authorize?: false
               ) do
          {:ok, updated}
        end
    end
  end

  defp record_transaction_event(transaction, event_type, source, actor) do
    Finance.record_bank_transaction_event(
      %{
        bank_transaction_id: transaction.id,
        event_type: event_type,
        source: event_source(source),
        amount: transaction.amount
      },
      actor: actor,
      authorize?: false
    )
  end

  defp event_source(:webhook), do: :sync
  defp event_source(:scheduled_sync), do: :sync
  defp event_source(:manual_sync), do: :sync
  defp event_source(:operator), do: :operator

  defp collect_results(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, account} -> account end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp empty_result(account_count) do
    %{
      accounts_seen_count: account_count,
      transactions_seen_count: 0,
      transactions_created_count: 0,
      transactions_updated_count: 0
    }
  end

  defp empty_account_result do
    %{
      transactions_seen_count: 0,
      transactions_created_count: 0,
      transactions_updated_count: 0,
      errors: []
    }
  end

  defp provider_opts(%{environment: :sandbox}), do: [sandbox?: true]
  defp provider_opts(_connection), do: []

  defp default_connection_name(:mercury, :sandbox), do: "Mercury Sandbox"
  defp default_connection_name(:mercury, :production), do: "Mercury Production"
  defp default_connection_name(provider, environment), do: "#{provider} #{environment}"

  defp not_found_error?(error) do
    Exception.message(error) =~ "record not found" or
      Exception.message(error) =~ "No such resource"
  end
end
