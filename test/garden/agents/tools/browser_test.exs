defmodule GnomeGarden.Agents.Tools.BrowserTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Agents.Tools.Browser

  setup do
    original_mode = Application.get_env(:gnome_garden, :browser_mode)
    original_display = System.get_env("DISPLAY")

    on_exit(fn ->
      if is_nil(original_mode) do
        Application.delete_env(:gnome_garden, :browser_mode)
      else
        Application.put_env(:gnome_garden, :browser_mode, original_mode)
      end

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

  test "can be forced into headed mode" do
    Application.put_env(:gnome_garden, :browser_mode, :headed)
    System.delete_env("DISPLAY")

    assert "--headed" in Browser.default_args()
  end
end
