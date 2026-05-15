defmodule GnomeGarden.Finance.Changes.GenerateStripePaymentLink do
  @moduledoc """
  Ash.Resource.Change that generates a Stripe Payment Link after invoice issue.
  Attached to the :issue action on Invoice as the last change.
  Non-fatal: if Stripe is unavailable, logs a warning and continues.
  ACH payment is always available regardless.
  """

  use Ash.Resource.Change
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
      case GnomeGarden.Payments.StripeClient.create_payment_link(invoice) do
        {:ok, url} ->
          case Ash.update(invoice, %{stripe_payment_url: url},
                 action: :update, domain: GnomeGarden.Finance, authorize?: false) do
            {:ok, updated} -> {:ok, updated}
            {:error, _} -> {:ok, invoice}
          end

        {:error, reason} ->
          Logger.warning("GenerateStripePaymentLink: #{inspect(reason)}")
          {:ok, invoice}
      end
    end)
  end
end
