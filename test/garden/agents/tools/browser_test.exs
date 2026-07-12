defmodule GnomeGarden.BrowserTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Browser

  @moduletag :tmp_dir

  setup do
    original_mode = Application.get_env(:gnome_garden, :browser_mode)
    original_path = Application.get_env(:gnome_garden, :browser_path)
    original_roots = Application.get_env(:gnome_garden, :browser_binary_roots)
    original_display = System.get_env("DISPLAY")

    on_exit(fn ->
      restore_app_env(:browser_mode, original_mode)
      restore_app_env(:browser_path, original_path)
      restore_app_env(:browser_binary_roots, original_roots)

      if is_nil(original_display) do
        System.delete_env("DISPLAY")
      else
        System.put_env("DISPLAY", original_display)
      end
    end)

    :ok
  end

  test "defaults to headless args when no display is available" do
    Application.put_env(:gnome_garden, :browser_mode, :auto)
    System.delete_env("DISPLAY")

    refute "--headed" in Browser.default_args()
  end

  test "auto mode remains headless when a display is available" do
    Application.put_env(:gnome_garden, :browser_mode, :auto)
    System.put_env("DISPLAY", ":0")

    refute "--headed" in Browser.default_args()
  end

  test "can be forced into headed mode" do
    Application.put_env(:gnome_garden, :browser_mode, :headed)
    System.delete_env("DISPLAY")

    assert "--headed" in Browser.default_args()
  end

  test "finds agent-browser under a configured vendored root", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "release")
    binary = Path.join([root, "jido_browser-linux_amd64", "agent-browser-linux-x64"])

    File.mkdir_p!(Path.dirname(binary))
    File.write!(binary, "")
    File.chmod!(binary, 0o755)

    Application.delete_env(:gnome_garden, :browser_path)
    Application.put_env(:gnome_garden, :browser_binary_roots, [root])

    assert Browser.binary_path() == binary
  end

  test "uses the immutable runtime-configured browser path" do
    path = "/nix/store/test-agent-browser/bin/agent-browser"
    Application.put_env(:gnome_garden, :browser_path, path)

    assert Browser.binary_path() == path
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_app_env(key, value), do: Application.put_env(:gnome_garden, key, value)
end
