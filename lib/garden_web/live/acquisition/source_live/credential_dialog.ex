defmodule GnomeGardenWeb.Acquisition.SourceLive.CredentialDialog do
  @moduledoc false

  use GnomeGardenWeb, :html

  attr :dialog, :map, required: true
  attr :form, :map, required: true

  def credential_modal(assigns) do
    ~H"""
    <.modal id="source-credential-modal" on_cancel={JS.push("close_credential_form")}>
      <:title>Source Credentials</:title>

      <.form
        for={@form}
        id="source-credential-form"
        phx-change="validate_credential"
        phx-submit="save_credential"
        class="space-y-4"
      >
        <.input field={@form[:provider]} type="hidden" />
        <.input field={@form[:credential_family]} type="hidden" />
        <.input field={@form[:scope]} type="hidden" />
        <.input field={@form[:label]} type="hidden" />

        <div class="rounded-md border border-base-content/10 bg-base-200/70 px-3 py-2">
          <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
            Source
          </p>
          <p class="mt-1 text-sm font-medium text-base-content">{@dialog.source_name}</p>
          <p class="mt-0.5 text-xs text-base-content/55">{@dialog.family_label}</p>
        </div>

        <.input
          field={@form[:credential_storage]}
          type="select"
          label="Storage"
          options={[
            {"Encrypted in Gnome Garden", "local_encrypted"},
            {"Bitwarden item reference", "bitwarden"}
          ]}
        />

        <.input
          :if={local_storage?(@form) and @dialog.secret_kind == :api_key}
          field={@form[:api_key]}
          type="password"
          label="API Key"
          autocomplete="new-password"
        />

        <div
          :if={local_storage?(@form) and @dialog.secret_kind == :username_password}
          class="grid gap-4 sm:grid-cols-2"
        >
          <.input
            field={@form[:username]}
            type="text"
            label="Username"
            autocomplete="username"
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
          />
        </div>

        <div
          :if={bitwarden_storage?(@form)}
          class="rounded-md border border-base-content/10 bg-base-100 p-3"
        >
          <p class="text-sm font-semibold text-base-content">Bitwarden Reference</p>
          <div class="mt-3 grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:bitwarden_server_url]}
              type="text"
              label="Server URL"
              placeholder="https://garden.tail6f3b43.ts.net"
            />
            <.input
              field={@form[:bitwarden_organization]}
              type="text"
              label="Organization"
              placeholder="Gnome Garden"
            />
            <.input
              field={@form[:bitwarden_collection]}
              type="text"
              label="Collection"
              placeholder="Procurement Sources"
            />
            <.input
              field={@form[:bitwarden_item_name]}
              type="text"
              label="Item Name"
              placeholder={@dialog.family_label}
            />
            <.input field={@form[:bitwarden_item_id]} type="text" label="Item ID" />
          </div>
          <.input
            field={@form[:bitwarden_notes]}
            type="textarea"
            label="Reference Notes"
            rows="2"
          />
        </div>

        <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />

        <div class="flex flex-wrap items-center justify-end gap-2 pt-1">
          <button
            type="button"
            phx-click="close_credential_form"
            class="inline-flex items-center justify-center rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm font-semibold text-zinc-800 shadow-sm transition hover:border-zinc-400 hover:bg-zinc-50 dark:border-white/10 dark:bg-white/[0.04] dark:text-white dark:hover:border-white/20 dark:hover:bg-white/[0.08]"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="inline-flex items-center justify-center rounded-md border border-emerald-600 bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:border-emerald-500 hover:bg-emerald-500 dark:border-emerald-500 dark:bg-emerald-500 dark:hover:border-emerald-400 dark:hover:bg-emerald-400"
          >
            Save & Test Credentials
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp local_storage?(form), do: not bitwarden_storage?(form)

  defp bitwarden_storage?(form) do
    Phoenix.HTML.Form.input_value(form, :credential_storage) in [:bitwarden, "bitwarden"]
  end
end
