defmodule GnomeGardenWeb.Acquisition.CollectionQueries do
  @moduledoc false

  alias GnomeGarden.Acquisition.Finding

  require Ash.Query

  def source_search(query, _searchable_columns, term) do
    term = "%#{String.trim(term)}%"

    Ash.Query.filter(
      query,
      fragment("? ILIKE ?", name, ^term) or
        fragment("? ILIKE ?", url, ^term) or
        fragment("? ILIKE ?", description, ^term) or
        fragment("? ILIKE ?", external_ref, ^term) or
        fragment("?::text ILIKE ?", source_family, ^term) or
        fragment("?::text ILIKE ?", source_kind, ^term) or
        fragment("?::text ILIKE ?", scan_strategy, ^term) or
        fragment("? ILIKE ?", procurement_source.name, ^term) or
        fragment("? ILIKE ?", procurement_source.url, ^term) or
        fragment("? ILIKE ?", procurement_source.portal_id, ^term) or
        fragment("?::text ILIKE ?", procurement_source.source_type, ^term)
    )
  end

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
