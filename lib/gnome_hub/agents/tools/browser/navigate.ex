defmodule GnomeHub.Agents.Tools.Browser.Navigate do
  @moduledoc """
  Navigate to a URL and return page info.
  """

  use Jido.Action,
    name: "browser_navigate",
    description: "Navigate to a URL and get page title. Returns basic page info.",
    schema: [
      url: [type: :string, required: true, doc: "URL to navigate to"],
      wait_for_network: [type: :boolean, default: true, doc: "Wait for network idle after navigation"]
    ]

  @browser_path "/home/pc/gnome/gnome_hub/_build/jido_browser-linux_amd64/agent-browser-linux-x64"
  @browser_args ["--headed", "--args", "--no-sandbox,--disable-blink-features=AutomationControlled"]

  @impl true
  def run(%{url: url} = params, _context) do
    wait_for_network = Map.get(params, :wait_for_network, true)

    # Navigate to URL
    case System.cmd(@browser_path, @browser_args ++ ["open", url, "--timeout", "30000"], stderr_to_stdout: true) do
      {output, 0} ->
        title = parse_title(output)

        # Wait for network idle if requested (important for SPAs)
        if wait_for_network do
          System.cmd(@browser_path, ["wait", "--load", "networkidle", "--timeout", "30000"], stderr_to_stdout: true)
        end

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
