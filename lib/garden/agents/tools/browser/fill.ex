defmodule GnomeGarden.Agents.Tools.Browser.Fill do
  @moduledoc """
  Fill a form field with text.
  """

  use Jido.Action,
    name: "browser_fill",
    description: "Fill a form field with text (clears existing content first)",
    schema: [
      ref: [type: :string, required: true, doc: "Element ref like '@e12' or CSS selector"],
      text: [type: :string, required: true, doc: "Text to fill in"]
    ]

  alias GnomeGarden.Agents.Tools.Browser

  @impl true
  def run(%{ref: ref, text: text}, _context) do
    ref = if String.match?(ref, ~r/^e\d+$/), do: "@#{ref}", else: ref

    case System.cmd(Browser.binary_path(), ["fill", ref, text], stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, %{filled: ref, text: text, status: :ok}}

      {output, _} ->
        {:error, "Fill failed: #{String.trim(output)}"}
    end
  end
end
