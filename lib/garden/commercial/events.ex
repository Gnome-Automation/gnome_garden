defmodule GnomeGarden.Commercial.Events do
  @moduledoc """
  Commercial event logging helpers.

  Keeps audit logging out of the Ash domain module while preserving a single
  place to thread actor context into event writes.
  """

  alias GnomeGarden.Commercial.Event

  def log(attrs, opts \\ []) do
    Ash.create(Event, attrs, actor_opts(opts))
  end

  defp actor_opts(opts) do
    case Keyword.get(opts, :actor) do
      nil -> []
      actor -> [actor: actor]
    end
  end
end
