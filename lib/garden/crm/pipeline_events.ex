defmodule GnomeGarden.CRM.PipelineEvents do
  @moduledoc """
  CRM pipeline event logging helpers.

  Keeps audit logging out of the Ash domain module while preserving a single
  place to thread actor context into event writes.
  """

  alias GnomeGarden.Sales.Event

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
