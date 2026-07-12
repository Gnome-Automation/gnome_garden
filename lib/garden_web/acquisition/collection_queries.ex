defmodule GnomeGardenWeb.Acquisition.CollectionQueries do
  @moduledoc false

  alias GnomeGarden.Acquisition.Finding

  def finding(queue, family, source_id, program_id, run_id) do
    Ash.Query.for_read(Finding, :queue, %{
      queue: queue,
      family: family,
      source_id: source_id,
      program_id: program_id,
      agent_run_id: run_id
    })
  end
end
