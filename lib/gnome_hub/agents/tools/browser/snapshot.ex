defmodule GnomeHub.Agents.Tools.Browser.Snapshot do
  @moduledoc """
  Get accessibility tree snapshot of current page.

  Returns a structured view of the page with clickable refs.
  Use this to understand page structure before interacting.
  """

  use Jido.Action,
    name: "browser_snapshot",
    description: "Get page structure with clickable element refs. Use to understand what's on the page.",
    schema: []

  @browser_path "/home/pc/gnome/gnome_hub/_build/jido_browser-linux_amd64/agent-browser-linux-x64"

  @impl true
  def run(_params, _context) do
    case System.cmd(@browser_path, ["snapshot"], stderr_to_stdout: true) do
      {output, 0} ->
        # Truncate if too long
        snapshot = if String.length(output) > 8000 do
          String.slice(output, 0, 8000) <> "\n... (truncated)"
        else
          output
        end
        {:ok, %{snapshot: snapshot}}

      {output, _} ->
        {:error, "Snapshot failed: #{output}"}
    end
  end
end
