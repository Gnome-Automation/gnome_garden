defmodule GnomeGarden.Mercury.PaymentMatcherWorker do
  @moduledoc """
  Oban worker that matches a Mercury transaction to Finance.Payment records.

  Enqueued by MercuryWebhookController when a `transaction.created` event arrives.
  The actual matching logic is implemented in a future feature — this stub
  acknowledges the job and logs it.
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => transaction_id}}) do
    Logger.info("PaymentMatcherWorker: queued for transaction #{transaction_id}")
    :ok
  end
end
