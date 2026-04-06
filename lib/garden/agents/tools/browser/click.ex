defmodule GnomeGarden.Agents.Tools.Browser.Click do
  @moduledoc """
  Click an element on the page by ref.
  """

  use Jido.Action,
    name: "browser_click",
    description: "Click an element using its ref from snapshot (e.g., '@e9')",
    schema: [
      ref: [type: :string, required: true, doc: "Element ref like '@e9' or CSS selector"]
    ]

  alias GnomeGarden.Agents.Tools.Browser

  @impl true
  def run(%{ref: ref}, _context) do
    ref = if String.match?(ref, ~r/^e\d+$/), do: "@#{ref}", else: ref

    case System.cmd(Browser.binary_path(), ["click", ref], stderr_to_stdout: true) do
      {_output, 0} ->
        # Wait a moment for page to update
        Process.sleep(1500)
        {:ok, %{clicked: ref, status: :ok}}

      {output, _} ->
        {:error, "Click failed: #{String.trim(output)}"}
    end
  end
end
