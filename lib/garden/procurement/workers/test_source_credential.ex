defmodule GnomeGarden.Procurement.Workers.TestSourceCredential do
  @moduledoc """
  Oban worker that verifies stored procurement source credentials.
  """

  use Oban.Worker,
    queue: :procurement_configuring,
    max_attempts: 1,
    unique: [period: 60, fields: [:worker, :args]]

  require Logger

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourceCredentialTesting

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "source_credential_id" => credential_id,
          "procurement_source_id" => procurement_source_id
        }
      }) do
    with {:ok, credential} <- Procurement.get_source_credential(credential_id, authorize?: false),
         {:ok, testing_credential} <-
           Procurement.mark_source_credential_test_running(credential, %{}, authorize?: false) do
      case SourceCredentialTesting.test_credential(testing_credential,
             procurement_source_id: procurement_source_id
           ) do
        {:ok, result} ->
          Logger.info("Source credential verified",
            credential_id: credential_id,
            provider: testing_credential.provider,
            result: inspect(result)
          )

          Procurement.mark_source_credential_verified(testing_credential, %{}, authorize?: false)
          :ok

        {:error, reason} ->
          formatted_reason = SourceCredentialTesting.format_reason(reason)

          Logger.warning("Source credential verification failed",
            credential_id: credential_id,
            provider: testing_credential.provider,
            reason: formatted_reason
          )

          Procurement.mark_source_credential_failed(
            testing_credential,
            %{last_failure_reason: formatted_reason},
            authorize?: false
          )

          :ok
      end
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, {:unexpected_args, args}}
  end
end
