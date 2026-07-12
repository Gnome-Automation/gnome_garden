defmodule GnomeGarden.Acquisition.Preparations.SourceConsole do
  @moduledoc false
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, opts, _context) do
    Ash.Query.build(query,
      sort: [status: :asc, last_run_at: :desc, inserted_at: :desc],
      load: opts[:loads]
    )
  end
end
