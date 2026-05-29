defmodule GnomeGarden.Finance.Notifiers.CreditNoteGLNotifier do
  @moduledoc """
  Auto-posts a GL entry when a credit note is manually issued.
  Skips posting if the parent invoice is voided (void JE already reversed revenue).
  """

  use Ash.Notifier

  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.GLPoster

  @impl true
  def notify(%Ash.Notifier.Notification{action: %{name: :issue}, data: credit_note}) do
    case Finance.get_invoice(credit_note.invoice_id, authorize?: false) do
      {:ok, invoice} ->
        GLPoster.post_credit_note_issued(credit_note, invoice)

      _ ->
        :ok
    end

    :ok
  end

  def notify(_), do: :ok
end
