defmodule GnomeGardenWeb.Finance.MercuryAliasLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Mercury
  alias GnomeGarden.Operations

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Aliases")
     |> assign(:aliases, load_aliases(socket.assigns.current_user))
     |> assign(:organizations, load_organizations(socket.assigns.current_user))
     |> assign(:new_fragment, "")
     |> assign(:new_org_id, "")
     |> assign(:form_error, nil)
     |> assign(:form_key, System.unique_integer([:positive]))}
  end

  @impl true
  def handle_event("add_alias", %{"fragment" => fragment, "org_id" => org_id}, socket) do
    fragment = String.trim(fragment)
    actor = socket.assigns.current_user

    cond do
      fragment == "" ->
        {:noreply, assign(socket, :form_error, "Counterparty name fragment is required.")}

      org_id == "" ->
        {:noreply, assign(socket, :form_error, "Organization is required.")}

      true ->
        case Mercury.create_client_bank_alias(
               %{counterparty_name_fragment: fragment, organization_id: org_id},
               actor: actor,
               authorize?: false
             ) do
          {:ok, alias} ->
            Mercury.create_alias_event(%{
              action: :created,
              actor_id: actor.id,
              counterparty_name_fragment: alias.counterparty_name_fragment,
              organization_id: alias.organization_id
            }, actor: actor, authorize?: false)

            {:noreply,
             socket
             |> assign(:aliases, load_aliases(actor))
             |> assign(:form_error, nil)
             |> push_event("reset-form", %{id: "alias-add-form"})
             |> put_flash(:info, "Alias added.")}

          {:error, %Ash.Error.Invalid{} = error} ->
            msg =
              error.errors
              |> Enum.map(& &1.message)
              |> Enum.join(", ")

            {:noreply, assign(socket, :form_error, "Could not add alias: #{msg}")}

          {:error, reason} ->
            Logger.warning("create_client_bank_alias failed: #{inspect(reason)}")
            {:noreply, assign(socket, :form_error, "Could not add alias.")}
        end
    end
  end

  @impl true
  def handle_event("delete_alias", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    alias_record = Enum.find(socket.assigns.aliases, &(&1.id == id))

    case Mercury.delete_client_bank_alias(id, actor: actor, authorize?: false) do
      {:ok, _} ->
        if alias_record do
          Mercury.create_alias_event(%{
            action: :deleted,
            actor_id: actor.id,
            counterparty_name_fragment: alias_record.counterparty_name_fragment,
            organization_id: alias_record.organization_id
          }, actor: actor, authorize?: false)
        end

        {:noreply,
         socket
         |> assign(:aliases, load_aliases(actor))
         |> put_flash(:info, "Alias removed.")}

      {:error, reason} ->
        Logger.warning("delete_client_bank_alias failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not remove alias.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Bank Aliases
        <:subtitle>
          Map wire/ACH counterparty name fragments to organizations. The auto-matcher uses these to link incoming transactions to the right client.
        </:subtitle>
      </.page_header>

      <div class="max-w-3xl space-y-6">
        <%!-- Add alias form --%>
        <.section title="Add Alias" description="Add a new counterparty name fragment → organization mapping.">
          <div class="px-5 pb-5">
            <form id="alias-add-form" phx-submit="add_alias" class="flex flex-wrap items-start gap-3">
              <div class="flex-1 min-w-48">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                  Counterparty Name Fragment
                </label>
                <input
                  type="text"
                  name="fragment"
                  value={@new_fragment}
                  placeholder="e.g. ACME CORP"
                  class="mt-1 w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500"
                />
                <p class="mt-1 text-xs text-base-content/50">Partial match — "ACME" will match "ACME CORP", "ACME INC", etc.</p>
              </div>
              <div class="flex-1 min-w-48">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                  Organization
                </label>
                <div class="mt-1 grid grid-cols-1">
                  <select
                    name="org_id"
                    class="col-start-1 row-start-1 appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                  >
                    <option value="">Select organization...</option>
                    <option :for={org <- @organizations} value={org.id}>{org.name}</option>
                  </select>
                  <svg class="pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end text-gray-500" viewBox="0 0 16 16" fill="currentColor">
                    <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
                  </svg>
                </div>
              </div>
              <div class="pt-6">
                <button
                  type="submit"
                  class="rounded-md border border-emerald-600 bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:border-emerald-500 hover:bg-emerald-500 active:scale-95 dark:border-emerald-500 dark:bg-emerald-500 dark:hover:border-emerald-400 dark:hover:bg-emerald-400"
                >
                  Add Alias
                </button>
              </div>
            </form>
            <div :if={@form_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-600 dark:bg-red-900/30 dark:text-red-400">
              {@form_error}
            </div>
          </div>
        </.section>

        <%!-- Alias list --%>
        <.section title="Existing Aliases" body_class="p-0">
          <div :if={@aliases == []} class="p-6 sm:p-7">
            <.empty_state
              icon="hero-tag"
              title="No aliases yet"
              description="Add an alias above to start mapping counterparty names to organizations."
            />
          </div>
          <div :if={@aliases != []} class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
              <thead class="bg-zinc-50 dark:bg-white/[0.03]">
                <tr>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Counterparty Fragment</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Organization</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">Added</th>
                  <th class="px-5 py-3"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
                <tr :for={a <- @aliases}>
                  <td class="px-5 py-4 font-mono text-sm text-zinc-900 dark:text-white">
                    {a.counterparty_name_fragment}
                  </td>
                  <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">
                    {(a.organization && a.organization.name) || "—"}
                  </td>
                  <td class="px-5 py-4 text-zinc-500 dark:text-zinc-400">
                    {format_date(DateTime.to_date(a.inserted_at))}
                  </td>
                  <td class="px-5 py-4 text-right">
                    <button
                      phx-click="delete_alias"
                      phx-value-id={a.id}
                      data-confirm="Remove this alias? The auto-matcher will no longer use it."
                      class="rounded-md border border-red-300 px-2.5 py-1 text-xs font-semibold text-red-600 hover:bg-red-50 dark:border-red-500/50 dark:text-red-400 dark:hover:bg-red-900/20 cursor-pointer transition-colors"
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  defp load_aliases(actor) do
    case Mercury.list_client_bank_aliases(actor: actor, authorize?: false, load: [:organization]) do
      {:ok, aliases} -> Enum.sort_by(aliases, & &1.counterparty_name_fragment)
      {:error, _} -> []
    end
  end

  defp load_organizations(actor) do
    case Operations.list_organizations(actor: actor) do
      {:ok, orgs} -> Enum.sort_by(orgs, &String.downcase(&1.name || ""))
      {:error, _} -> []
    end
  end
end
