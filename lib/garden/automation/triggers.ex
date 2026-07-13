defmodule GnomeGarden.Automation.Triggers do
  @moduledoc """
  The whitelist of instrumented trigger points. Rules may only reference
  these — a typo'd trigger is rejected at write time instead of silently
  never firing.
  """

  @known [
    {"bid", "scored", "Bid scored (tier changed)"},
    {"bid", "due_soon", "Bid deadline approaching"},
    {"pursuit", "qualified", "Pursuit qualified"},
    {"pursuit", "proposed", "Pursuit proposed"},
    {"source_credential", "failed", "Source credential failed"},
    {"task", "overdue", "Task overdue"}
  ]

  def known?(resource, action),
    do: Enum.any?(@known, fn {r, a, _label} -> r == resource and a == action end)

  def options,
    do: Enum.map(@known, fn {resource, action, label} -> {label, "#{resource}|#{action}"} end)

  def describe,
    do: Enum.map_join(@known, ", ", fn {resource, action, _label} -> "#{resource}.#{action}" end)
end
