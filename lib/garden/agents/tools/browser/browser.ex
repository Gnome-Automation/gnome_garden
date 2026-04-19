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
    browser_mode_args() ++
      ["--args", "--no-sandbox,--disable-blink-features=AutomationControlled"]
  end

  @doc "Close the browser daemon if it is running."
  def close do
    System.cmd(binary_path(), ["close"], stderr_to_stdout: true)
  end

  @doc "Whether the browser output indicates a stale daemon prevented relaunch."
  def restart_required?(output) when is_binary(output) do
    String.contains?(output, "--args ignored: daemon already running") or
      String.contains?(output, "Event stream closed")
  end

  defp browser_mode_args do
    case Application.get_env(:gnome_garden, :browser_mode, :auto) do
      :headed ->
        ["--headed"]

      :headless ->
        []

      :auto ->
        if System.get_env("DISPLAY") do
          ["--headed"]
        else
          []
        end
    end
  end

  defp default_path do
    build_root =
      Application.app_dir(:gnome_garden)
      |> Path.join("../../..")
      |> Path.expand()

    Path.join([build_root, "jido_browser-linux_amd64", "agent-browser-linux-x64"])
  end
end
