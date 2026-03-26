defmodule GnomeHub.Agents.Tools.Browser.Navigate do
  @moduledoc """
  Navigate to a URL and return page info.
  """

  use Jido.Action,
    name: "browser_navigate",
    description: "Navigate to a URL and get page title. Returns basic page info.",
    schema: [
      url: [type: :string, required: true, doc: "URL to navigate to"]
    ]

  @browser_path "/home/pc/gnome/gnome_hub/_build/jido_browser-linux_amd64/agent-browser-linux-x64"

  @impl true
  def run(%{url: url}, _context) do
    case System.cmd(@browser_path, ["open", url, "--timeout", "20000"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse title from output like "[32m✓[0m [1mPage Title[0m"
        title = parse_title(output)
        {:ok, %{url: url, title: title, status: :ok}}

      {output, _} ->
        {:ok, %{url: url, title: nil, status: :error, error: String.trim(output)}}
    end
  end

  defp parse_title(output) do
    case Regex.run(~r/\[1m(.+?)\[0m/, output) do
      [_, title] -> title
      _ -> "Unknown"
    end
  end
end
