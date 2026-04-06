defmodule GnomeGardenWeb.CRM.Helpers do
  @moduledoc """
  Shared formatting helpers for CRM LiveViews.
  """

  def format_atom(nil), do: "-"

  def format_atom(atom),
    do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

  def format_region(nil), do: "-"
  def format_region(region), do: region |> to_string() |> String.upcase()

  def format_source(nil), do: "-"
  def format_source(source), do: source |> to_string() |> String.replace("_", " ")

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")
  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")

  def format_datetime(nil), do: "-"
  def format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

  def format_amount(nil), do: "-"
  def format_amount(amount), do: "$#{Decimal.to_string(amount)}"

  # Map Ash atom status values to Protocol status_badge status atoms
  def lead_status(:new), do: :info
  def lead_status(:contacted), do: :info
  def lead_status(:qualified), do: :success
  def lead_status(:unqualified), do: :warning
  def lead_status(:converted), do: :success
  def lead_status(_), do: :default

  def contact_status(:active), do: :success
  def contact_status(:inactive), do: :warning
  def contact_status(_), do: :default

  def task_priority(:urgent), do: :error
  def task_priority(:high), do: :warning
  def task_priority(:normal), do: :info
  def task_priority(:low), do: :default
  def task_priority(_), do: :default

  def task_status(:completed), do: :success
  def task_status(:in_progress), do: :info
  def task_status(:pending), do: :warning
  def task_status(:cancelled), do: :default
  def task_status(_), do: :default

  def opportunity_stage(:discovery), do: :info
  def opportunity_stage(:qualification), do: :info
  def opportunity_stage(:demo), do: :warning
  def opportunity_stage(:proposal), do: :warning
  def opportunity_stage(:negotiation), do: :info
  def opportunity_stage(:closed_won), do: :success
  def opportunity_stage(:closed_lost), do: :error
  def opportunity_stage(_), do: :default

  def overdue?(nil, _status), do: false
  def overdue?(_due_at, :completed), do: false
  def overdue?(_due_at, :cancelled), do: false

  def overdue?(due_at, _status) do
    DateTime.compare(due_at, DateTime.utc_now()) == :lt
  end
end
