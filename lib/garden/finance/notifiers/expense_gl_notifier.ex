defmodule GnomeGarden.Finance.Notifiers.ExpenseGLNotifier do
  @moduledoc """
  Auto-posts a GL entry when an expense is approved.
  """

  use Ash.Notifier

  alias GnomeGarden.Finance.GLPoster

  @impl true
  def notify(%Ash.Notifier.Notification{action: %{name: :approve}, data: expense}) do
    GLPoster.post_expense_approved(expense)
    :ok
  end

  def notify(_), do: :ok
end
