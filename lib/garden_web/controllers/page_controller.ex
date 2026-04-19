defmodule GnomeGardenWeb.PageController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Execution

  def home(conn, _params) do
    due_soon_maintenance_plans =
      list_due_soon_maintenance_plans(conn.assigns[:current_user])

    render(conn, :home,
      layout: {GnomeGardenWeb.Layouts, :app},
      page_title: "Dashboard",
      current_user: conn.assigns[:current_user],
      current_path: conn.request_path,
      due_soon_maintenance_count: length(due_soon_maintenance_plans),
      due_soon_maintenance_plans: due_soon_maintenance_plans
    )
  end

  defp list_due_soon_maintenance_plans(actor) do
    case Execution.list_due_soon_maintenance_plans(30,
           actor: actor,
           load: [:due_status_variant, :due_status_label, asset: [], organization: []]
         ) do
      {:ok, maintenance_plans} -> Enum.take(maintenance_plans, 5)
      {:error, _error} -> []
    end
  end
end
