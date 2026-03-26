defmodule GnomeHub.Agents.Tools.Browser.Extract do
  @moduledoc """
  Extract data from current page using JavaScript.
  """

  use Jido.Action,
    name: "browser_extract",
    description: "Run JavaScript to extract data from the page. Returns JSON result.",
    schema: [
      js: [type: :string, required: true, doc: "JavaScript code to run. Should return data."]
    ]

  @browser_path "/home/pc/gnome/gnome_hub/_build/jido_browser-linux_amd64/agent-browser-linux-x64"

  @impl true
  def run(%{js: js}, _context) do
    case System.cmd(@browser_path, ["eval", js], stderr_to_stdout: true) do
      {output, 0} ->
        # Try to parse as JSON
        case Jason.decode(output) do
          {:ok, data} -> {:ok, %{data: data}}
          {:error, _} -> {:ok, %{data: String.trim(output)}}
        end

      {output, _} ->
        {:error, "Extract failed: #{String.trim(output)}"}
    end
  end
end
