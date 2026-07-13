defmodule GnomeGarden.Procurement.BrowserSessionCustody do
  @moduledoc "Materializes encrypted browser state only for the duration of one operation."

  alias GnomeGarden.Procurement

  def with_materialized(session, function) when is_function(function, 1) do
    with {:ok, storage_state} <-
           Procurement.resolve_source_browser_session_state(
             session.id,
             session.procurement_source_id,
             session.source_credential_id,
             authorize?: false
           ) do
      with_private_file(storage_state, function)
    end
  end

  defp with_private_file(storage_state, function) do
    dir = Path.join(System.tmp_dir!(), "garden-browser-state-#{Ecto.UUID.generate()}")
    path = Path.join(dir, "storage-state.json")

    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    File.write!(path, storage_state)
    File.chmod!(path, 0o600)

    try do
      function.(path)
    after
      File.rm_rf(dir)
    end
  end
end
