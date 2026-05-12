defmodule GnomeGardenWeb.Settings.UserLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Operations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> load_team_members()}
  end

  @impl true
  def handle_event("activate", %{"id" => id}, socket) do
    {:noreply, update_status(socket, id, :active)}
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    {:noreply, update_status(socket, id, :inactive)}
  end

  def handle_event("make_admin", %{"id" => id}, socket) do
    {:noreply, update_role(socket, id, :admin)}
  end

  def handle_event("make_operator", %{"id" => id}, socket) do
    {:noreply, update_role(socket, id, :operator)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header>
        Users
        <:subtitle>
          Signed-in humans and their operator access. Passwords are still rotated from release env.
        </:subtitle>
      </.page_header>

      <.section compact>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-base-content/10 text-sm">
            <thead class="bg-base-200/70 text-left text-xs font-semibold uppercase text-base-content/60">
              <tr>
                <th class="px-4 py-3">Operator</th>
                <th class="px-4 py-3">Login</th>
                <th class="px-4 py-3">Role</th>
                <th class="px-4 py-3">Status</th>
                <th class="px-4 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/10">
              <tr :for={team_member <- @team_members}>
                <td class="px-4 py-3">
                  <div class="font-medium text-base-content">{team_member.display_name}</div>
                  <div class="text-xs text-base-content/50">{team_member.id}</div>
                </td>
                <td class="px-4 py-3">
                  {team_member.user && team_member.user.email}
                </td>
                <td class="px-4 py-3">
                  <.status_badge status={role_variant(team_member.role)}>
                    {format_atom(team_member.role)}
                  </.status_badge>
                </td>
                <td class="px-4 py-3">
                  <.status_badge status={status_variant(team_member.status)}>
                    {format_atom(team_member.status)}
                  </.status_badge>
                </td>
                <td class="px-4 py-3">
                  <div class="flex flex-wrap justify-end gap-2">
                    <.button
                      :if={team_member.role != :admin}
                      phx-click="make_admin"
                      phx-value-id={team_member.id}
                    >
                      Make Admin
                    </.button>
                    <.button
                      :if={team_member.role == :admin}
                      phx-click="make_operator"
                      phx-value-id={team_member.id}
                    >
                      Make Operator
                    </.button>
                    <.button
                      :if={team_member.status != :active}
                      phx-click="activate"
                      phx-value-id={team_member.id}
                    >
                      Activate
                    </.button>
                    <.button
                      :if={team_member.status == :active}
                      phx-click="deactivate"
                      phx-value-id={team_member.id}
                    >
                      Deactivate
                    </.button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  defp load_team_members(socket) do
    team_members =
      Operations.list_admin_team_members!(actor: socket.assigns.current_user)

    assign(socket, :team_members, team_members)
  end

  defp update_status(socket, id, status) do
    with {:ok, team_member} <- Operations.get_team_member(id, actor: socket.assigns.current_user),
         {:ok, _team_member} <-
           Operations.update_team_member(team_member, %{status: status},
             actor: socket.assigns.current_user
           ) do
      load_team_members(socket)
    else
      {:error, error} ->
        put_flash(socket, :error, Exception.message(error))
    end
  end

  defp update_role(socket, id, role) do
    with {:ok, team_member} <- Operations.get_team_member(id, actor: socket.assigns.current_user),
         {:ok, _team_member} <-
           Operations.update_team_member(team_member, %{role: role},
             actor: socket.assigns.current_user
           ) do
      load_team_members(socket)
    else
      {:error, error} ->
        put_flash(socket, :error, Exception.message(error))
    end
  end

  defp role_variant(:admin), do: :success
  defp role_variant(:manager), do: :info
  defp role_variant(:agent_supervisor), do: :warning
  defp role_variant(_role), do: :default

  defp status_variant(:active), do: :success
  defp status_variant(:inactive), do: :warning
  defp status_variant(:archived), do: :error
  defp status_variant(_status), do: :default

  defp format_atom(nil), do: "-"

  defp format_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
