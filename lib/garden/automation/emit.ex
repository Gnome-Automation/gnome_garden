defmodule GnomeGarden.Automation.Emit do
  @moduledoc """
  Attachable Ash change that persists an `Automation.Event` for the action.

  The event insert happens in `after_action` — inside the same transaction as
  the business change — so the event and the change commit or roll back
  together. The snapshot contains only public, non-sensitive attributes,
  JSON-normalized so criteria comparisons are stable.

  Usage on a source resource action:

      change {GnomeGarden.Automation.Emit, resource: "bid", action: "scored"}

  The optional `when_changing: [:field, ...]` guard only emits when at least
  one listed attribute actually changes value — the tool against event spam
  from upserts and repeated no-op updates.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    if emit?(changeset, Keyword.get(opts, :when_changing)) do
      Ash.Changeset.after_action(changeset, fn _changeset, record ->
        attrs = %{
          resource: Keyword.fetch!(opts, :resource),
          action: Keyword.get(opts, :action, to_string(changeset.action.name)),
          record_id: record.id,
          data: snapshot(record),
          depth: automation_depth(record)
        }

        case GnomeGarden.Automation.record_automation_event(attrs, authorize?: false) do
          {:ok, _event} -> {:ok, record}
          {:error, error} -> {:error, error}
        end
      end)
    else
      changeset
    end
  end

  defp emit?(_changeset, nil), do: true
  defp emit?(%{action_type: :create}, _fields), do: true

  defp emit?(changeset, fields) do
    Enum.any?(fields, fn field ->
      Ash.Changeset.get_attribute(changeset, field) != Map.get(changeset.data, field)
    end)
  end

  defp snapshot(record) do
    record.__struct__
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reject(& &1.sensitive?)
    |> Map.new(fn attribute ->
      {to_string(attribute.name), normalize(Map.get(record, attribute.name))}
    end)
  end

  defp automation_depth(%{metadata: %{"automation_depth" => depth}}) when is_integer(depth),
    do: depth

  defp automation_depth(_record), do: 0

  defp normalize(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize(%Decimal{} = value), do: Decimal.to_string(value)
  defp normalize(%Money{} = value), do: Decimal.to_string(value.amount)
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  defp normalize(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, nested} -> {to_string(key), normalize(nested)} end)

  defp normalize(value) when is_struct(value), do: nil
  defp normalize(value), do: value
end
