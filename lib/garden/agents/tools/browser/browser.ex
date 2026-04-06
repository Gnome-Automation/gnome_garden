defmodule GnomeGarden.Agents.Tools.Browser do
  @moduledoc """
  Shared browser configuration for all browser tools.
  """

  @doc "Path to the jido_browser binary."
  def binary_path do
    Application.get_env(:gnome_garden, :browser_path, default_path())
  end

  @doc "Default browser launch args."
  def default_args do
    ["--headed", "--args", "--no-sandbox,--disable-blink-features=AutomationControlled"]
  end

  defp default_path do
    build_root =
      Application.app_dir(:gnome_garden)
      |> Path.join("../../..")
      |> Path.expand()

    Path.join([build_root, "jido_browser-linux_amd64", "agent-browser-linux-x64"])
  end
end
