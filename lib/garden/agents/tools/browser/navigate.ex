defmodule GnomeGarden.Agents.Tools.Browser.Navigate do
  @moduledoc """
  Navigate to a URL and return page info.
  """

  use Jido.Action,
    name: "browser_navigate",
    description: "Navigate to a URL and get page title. Returns basic page info.",
    schema: [
      url: [type: :string, required: true, doc: "URL to navigate to"],
      wait_for_network: [
        type: :boolean,
        default: true,
        doc: "Wait for network idle after navigation"
      ]
    ]

  alias GnomeGarden.Agents.Tools.Browser

  @impl true
  def run(%{url: url} = params, _context) do
    wait_for_network = Map.get(params, :wait_for_network, true)
    browser = Browser.binary_path()

    case System.cmd(browser, Browser.default_args() ++ ["open", url, "--timeout", "30000"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        title = parse_title(output)

        if wait_for_network do
          System.cmd(browser, ["wait", "--load", "networkidle", "--timeout", "30000"],
            stderr_to_stdout: true
          )
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
