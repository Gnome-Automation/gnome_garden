defmodule GnomeGarden.Agents.Tools.Browser.Press do
  @moduledoc """
  Press a keyboard key.
  """

  use Jido.Action,
    name: "browser_press",
    description: "Press a keyboard key (Enter, Tab, Escape, etc.)",
    schema: [
      key: [
        type: :string,
        required: true,
        doc: "Key to press: Enter, Tab, Escape, ArrowDown, etc."
      ]
    ]

  alias GnomeGarden.Agents.Tools.Browser

  @impl true
  def run(%{key: key}, _context) do
    case System.cmd(Browser.binary_path(), ["press", key], stderr_to_stdout: true) do
      {_output, 0} ->
        Process.sleep(500)
        {:ok, %{pressed: key, status: :ok}}

      {output, _} ->
        {:error, "Press failed: #{String.trim(output)}"}
    end
  end
end
