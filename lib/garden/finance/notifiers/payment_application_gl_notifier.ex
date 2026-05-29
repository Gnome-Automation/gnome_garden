defmodule GnomeGarden.Finance.Notifiers.PaymentApplicationGLNotifier do
  @moduledoc """
  Auto-posts a GL entry when a PaymentApplication is created (payment matched to invoice).
  """

  use Ash.Notifier

  alias GnomeGarden.Finance.GLPoster

  @impl true
  def notify(%Ash.Notifier.Notification{action: %{name: :create}, data: payment_application}) do
    GLPoster.post_payment_received(payment_application)
    :ok
  end

  def notify(_), do: :ok
end
