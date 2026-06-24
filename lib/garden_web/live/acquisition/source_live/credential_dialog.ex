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
          :if={@dialog.secret_kind == :api_key}
          field={@form[:api_key]}
          type="password"
          label="API Key"
          autocomplete="new-password"
          required
        />

        <div :if={@dialog.secret_kind == :username_password} class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@form[:username]}
            type="text"
            label="Username"
            autocomplete="username"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            required
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
end
