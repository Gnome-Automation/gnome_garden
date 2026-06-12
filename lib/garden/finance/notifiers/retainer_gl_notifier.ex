defmodule GnomeGarden.Finance.Notifiers.RetainerGLNotifier do
  @moduledoc """
  Ash notifier that auto-posts GL journal entries when retainer and retainer application
  state changes. Handles: retainer received, voided, retainer applied, unapplied.
  """

  use Ash.Notifier

  alias GnomeGarden.Finance.GLPoster

  @impl true
  def notify(%Ash.Notifier.Notification{
        resource: GnomeGarden.Finance.Retainer,
        action: %{name: :mark_paid},
        data: retainer
      }) do
    GLPoster.post_retainer_received(retainer)
    :ok
  end

  def notify(%Ash.Notifier.Notification{
        resource: GnomeGarden.Finance.Retainer,
        action: %{name: :void},
        data: retainer,
        changeset: changeset
      }) do
    # Check pre-transition status — retainer.status is already :void at this point
    if changeset.data.status == :paid do
      GLPoster.post_retainer_voided(retainer)
    end
    :ok
  end

  def notify(%Ash.Notifier.Notification{
        resource: GnomeGarden.Finance.RetainerApplication,
        action: %{name: :create},
        data: application
      }) do
    GLPoster.post_retainer_applied(application)
    :ok
  end

  def notify(%Ash.Notifier.Notification{
        resource: GnomeGarden.Finance.RetainerApplication,
        action: %{name: :destroy},
        data: application
      }) do
    GLPoster.post_retainer_unapplied(application)
    :ok
  end

  def notify(_), do: :ok
end
