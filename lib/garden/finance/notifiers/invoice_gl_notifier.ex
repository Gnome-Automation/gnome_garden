defmodule GnomeGarden.Finance.Notifiers.InvoiceGLNotifier do
  @moduledoc """
  Ash notifier that auto-posts GL journal entries when invoice state changes.
  Handles: invoice issued, voided, written off.
  """

  use Ash.Notifier

  alias GnomeGarden.Finance.GLPoster

  @impl true
  def notify(%Ash.Notifier.Notification{action: %{name: :issue}, data: invoice}) do
    GLPoster.post_invoice_issued(invoice)
    :ok
  end

  def notify(%Ash.Notifier.Notification{action: %{name: :void}, data: invoice, changeset: changeset}) do
    prior_status = changeset.data.status
    GLPoster.post_invoice_voided(invoice, prior_status)
    :ok
  end

  def notify(%Ash.Notifier.Notification{action: %{name: :write_off}, data: invoice, changeset: changeset}) do
    # Compute write-off amount BEFORE balance_amount was zeroed by the action
    prior_total = changeset.data.total_amount || Decimal.new("0")
    prior_applied = changeset.data.applied_amount || Decimal.new("0")
    write_off_amount = Decimal.sub(prior_total, prior_applied)

    if Decimal.positive?(write_off_amount) do
      GLPoster.post_invoice_written_off(invoice, write_off_amount)
    end

    :ok
  end

  def notify(_), do: :ok
end
