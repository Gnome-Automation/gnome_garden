defmodule GnomeGardenWeb.Operations.TaskPubSub do
  @moduledoc false

  @broad_topics ["task:created", "task:updated", "task:destroyed"]

  def subscribe_inbox do
    Enum.each(@broad_topics, &GnomeGardenWeb.Endpoint.subscribe/1)
  end

  def subscribe_task(task_id) when is_binary(task_id) do
    GnomeGardenWeb.Endpoint.subscribe("task:updated:#{task_id}")
    GnomeGardenWeb.Endpoint.subscribe("task:destroyed:#{task_id}")
  end

  def subscribe_related(_field, nil), do: :ok

  def subscribe_related(field, id) when is_atom(field) and is_binary(id) do
    GnomeGardenWeb.Endpoint.subscribe("task:#{field}:#{id}")
  end
end
