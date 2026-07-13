defmodule GnomeGardenWeb.Acquisition.SourceLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.OperationsUI,
    only: [related_tasks_panel: 1, playbook_runs_panel: 1]

  import GnomeGardenWeb.Execution.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourceCredential
  alias GnomeGarden.Procurement.SourceCredentials
  alias GnomeGardenWeb.Acquisition.SourceLive.CredentialDialog
  alias GnomeGardenWeb.Operations.TaskEntry
  alias GnomeGardenWeb.Operations.TaskPubSub

  @source_load [
    :procurement_source,
    :organization,
    :source_family_label,
    :source_kind_label,
    :scan_strategy_label,
    :status_label,
    :health_label,
    :health_note,
    :finding_count,
    :review_finding_count,
    :accepted_finding_count,
    :parked_finding_count,
    :rejected_finding_count,
    :promoted_finding_count,
    :latest_run_id,
    :health_status,
    :health_variant,
    :status_variant,
    :runnable
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("procurement_source_browser_session:created")
      GnomeGardenWeb.Endpoint.subscribe("procurement_source_browser_session:updated")
    end

    case load_source(id, socket.assigns.current_user) do
      {:ok, source} ->
        if connected?(socket) && source.procurement_source do
          TaskPubSub.subscribe_related(:procurement_source, source.procurement_source.id)

          GnomeGardenWeb.Endpoint.subscribe(
            "playbook_run:procurement_source:#{source.procurement_source.id}"
          )
        end

        {:ok,
         socket
         |> assign(:source, source)
         |> assign(:page_title, source.name)
         |> assign(:related_tasks, load_related_tasks(source, socket.assigns.current_user))
         |> assign_playbook_context(source)
         |> assign(:source_credential, credential_for_source(source))
         |> assign(:browser_session, browser_session_for_source(source))
         |> assign(:credential_dialog, nil)
         |> assign(:credential_form, nil)}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, "Source could not be loaded.")
         |> push_navigate(to: ~p"/acquisition/sources")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-6xl" class="pb-8">
      <.page_header eyebrow="Acquisition Source">
        {@source.name}
        <:subtitle>
          {@source.health_note || "Source configuration, queue health, and credentials."}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/acquisition/sources"} class="btn btn-sm btn-ghost">
            Sources
          </.link>
          <.link
            :if={procurement_source_id(@source)}
            navigate={~p"/acquisition/sources/#{procurement_source_id(@source)}/edit"}
            class="btn btn-sm btn-ghost"
          >
            Edit
          </.link>
          <button
            :if={credential_action_available?(@source)}
            type="button"
            id="source-show-credentials"
            phx-click="open_credential_form"
            class="btn btn-sm btn-primary"
          >
            <.icon name="hero-key" class="size-4" /> Credentials
          </button>
          <.link
            :if={procurement_source_id(@source)}
            navigate={~p"/acquisition/sources/#{@source.id}/configure"}
            class="btn btn-sm btn-ghost"
          >
            Configure
          </.link>
        </:actions>
      </.page_header>

      <.related_tasks_panel
        :if={@source.procurement_source}
        tasks={@related_tasks}
        description="Operator follow-up linked to this procurement source."
        empty_description="Credential fixes, configuration, and remediation tasks will appear here."
        new_task_path={new_source_task_path(@source)}
      />

      <.playbook_runs_panel
        :if={@source.procurement_source}
        runs={@playbook_runs}
        playbooks={@playbooks}
        description="Apply a playbook such as source remediation to create its task set."
      />

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-6">
          <.section title="Source Details" body_class="p-0">
            <dl class="divide-y divide-base-content/10">
              <.detail_row label="Status">
                <div class="flex flex-wrap gap-2">
                  <.status_badge status={@source.status_variant}>
                    {@source.status_label}
                  </.status_badge>
                  <.status_badge status={@source.health_variant}>
                    {@source.health_label}
                  </.status_badge>
                </div>
              </.detail_row>
              <.detail_row label="URL">
                <.link
                  href={@source.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="break-all text-primary hover:text-primary-focus hover:underline"
                >
                  {@source.url}
                </.link>
              </.detail_row>
              <.detail_row label="Family">{@source.source_family_label}</.detail_row>
              <.detail_row label="Kind">{@source.source_kind_label}</.detail_row>
              <.detail_row label="Scan Strategy">{@source.scan_strategy_label}</.detail_row>
              <.detail_row label="Last Run">{format_datetime(@source.last_run_at)}</.detail_row>
              <.detail_row label="Last Success">
                {format_datetime(@source.last_success_at)}
              </.detail_row>
              <.detail_row :if={@source.organization} label="Organization">
                {@source.organization.name}
              </.detail_row>
              <.detail_row :if={@source.description} label="Description">
                {@source.description}
              </.detail_row>
              <.detail_row :if={@source.latest_run_id} label="Latest Run">
                <.link
                  navigate={~p"/console/agents/runs/#{@source.latest_run_id}"}
                  class="text-primary hover:text-primary-focus hover:underline"
                >
                  {@source.latest_run_id}
                </.link>
              </.detail_row>
            </dl>
          </.section>

          <.section title="Procurement Source" body_class="p-0">
            <dl :if={@source.procurement_source} class="divide-y divide-base-content/10">
              <.detail_row label="Name">{@source.procurement_source.name}</.detail_row>
              <.detail_row label="Type">
                {format_atom(@source.procurement_source.source_type)}
              </.detail_row>
              <.detail_row label="Portal ID">
                {@source.procurement_source.portal_id || "Not set"}
              </.detail_row>
              <.detail_row label="Requires Login">
                {if @source.procurement_source.requires_login, do: "Yes", else: "No"}
              </.detail_row>
              <.detail_row label="Config Status">
                {format_atom(@source.procurement_source.config_status)}
              </.detail_row>
              <.detail_row label="Status">
                {format_atom(@source.procurement_source.status)}
              </.detail_row>
              <.detail_row label="Configured At">
                {format_datetime(@source.procurement_source.configured_at)}
              </.detail_row>
              <.detail_row label="Last Scanned">
                {format_datetime(@source.procurement_source.last_scanned_at)}
              </.detail_row>
              <.detail_row :if={@source.procurement_source.notes} label="Notes">
                {@source.procurement_source.notes}
              </.detail_row>
            </dl>
            <div :if={!@source.procurement_source} class="px-4 py-5 text-sm text-base-content/60">
              This acquisition source is not linked to a procurement source.
            </div>
          </.section>
        </div>

        <aside class="space-y-6">
          <.section title="Credentials" body_class="px-4 py-5">
            <div :if={@source_credential} class="space-y-3">
              <div class="flex flex-wrap items-center gap-2">
                <.status_badge status={credential_test_variant(@source_credential)}>
                  {credential_test_label(@source_credential)}
                </.status_badge>
                <span class="text-sm font-medium text-base-content">
                  {credential_family_label(@source_credential.credential_family)}
                </span>
              </div>
              <dl class="space-y-2 text-sm">
                <.compact_detail
                  label="Storage"
                  value={credential_storage_label(@source_credential)}
                />
                <.compact_detail label="Username" value={@source_credential.username || "Not set"} />
                <.compact_detail
                  :if={@source_credential.credential_storage == :bitwarden}
                  label="Bitwarden Item"
                  value={bitwarden_item_label(@source_credential)}
                />
                <.compact_detail
                  :if={@source_credential.credential_storage == :bitwarden}
                  label="Collection"
                  value={@source_credential.bitwarden_collection || "Not set"}
                />
                <.compact_detail label="Scope" value={format_atom(@source_credential.scope)} />
                <.compact_detail label="Provider" value={@source_credential.provider} />
                <.compact_detail
                  label="Last Tested"
                  value={format_datetime(credential_last_test_at(@source_credential))}
                />
              </dl>
              <p :if={@source_credential.last_failure_reason} class="text-sm text-error">
                {@source_credential.last_failure_reason}
              </p>
            </div>
            <p :if={!@source_credential} class="text-sm text-base-content/60">
              {if credential_action_available?(@source),
                do: "Credentials can be added for this source.",
                else: "This source does not currently require credentials."}
            </p>
            <button
              :if={credential_action_available?(@source)}
              type="button"
              phx-click="open_credential_form"
              class="btn btn-sm btn-primary mt-4 w-full"
            >
              <.icon name="hero-key" class="size-4" /> Add or Update Credentials
            </button>
          </.section>

          <.section :if={bidnet_source?(@source)} title="Browser Session" body_class="px-4 py-5">
            <div :if={@browser_session} class="space-y-3">
              <div class="flex flex-wrap items-center gap-2">
                <.status_badge status={browser_session_variant(@browser_session.status)}>
                  {format_atom(@browser_session.status)}
                </.status_badge>
                <span class="text-sm font-medium text-base-content">
                  {@browser_session.session_family}
                </span>
              </div>
              <dl class="space-y-2 text-sm">
                <.compact_detail
                  label="Verified"
                  value={format_datetime(@browser_session.verified_at)}
                />
                <.compact_detail label="Expires" value={format_datetime(@browser_session.expires_at)} />
                <.compact_detail
                  label="Credential"
                  value={session_credential_label(@browser_session, @source_credential)}
                />
              </dl>
              <p :if={@browser_session.last_failure_reason} class="text-sm text-error">
                {@browser_session.last_failure_reason}
              </p>
            </div>
            <p :if={!@browser_session} class="text-sm text-base-content/60">
              No authenticated browser session has been saved for this source.
            </p>
            <button
              type="button"
              phx-click="refresh_bidnet_session"
              class="btn btn-sm btn-primary mt-4 w-full"
              disabled={is_nil(@source_credential)}
              phx-disable-with="Refreshing..."
            >
              <.icon name="hero-arrow-path" class="size-4" /> Refresh Session
            </button>
          </.section>

          <.section title="Queue" body_class="px-4 py-5">
            <div class="grid grid-cols-2 gap-2">
              <.metric label="Total" value={@source.finding_count} />
              <.metric label="Review" value={@source.review_finding_count} />
              <.metric label="Accepted" value={@source.accepted_finding_count} />
              <.metric label="Promoted" value={@source.promoted_finding_count} />
              <.metric label="Parked" value={@source.parked_finding_count} />
              <.metric label="Rejected" value={@source.rejected_finding_count} />
            </div>
            <.link
              navigate={
                ~p"/acquisition/findings?family=#{@source.source_family}&source_id=#{@source.id}"
              }
              class="btn btn-sm btn-ghost mt-4 w-full"
            >
              Open Review Queue
            </.link>
          </.section>
        </aside>
      </div>

      <CredentialDialog.credential_modal
        :if={@credential_dialog}
        dialog={@credential_dialog}
        form={@credential_form}
      />
    </.page>
    """
  end

  @impl true
  def handle_event("open_credential_form", _params, socket) do
    {:noreply, assign_credential_form(socket, socket.assigns.source)}
  end

  @impl true
  def handle_event("close_credential_form", _params, socket) do
    {:noreply, clear_credential_form(socket)}
  end

  @impl true
  def handle_event("validate_credential", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.credential_form.source, params)
    {:noreply, assign(socket, :credential_form, to_form(form))}
  end

  @impl true
  def handle_event("save_credential", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.credential_form.source, params: params) do
      {:ok, credential} ->
        test_result =
          Procurement.queue_source_credential_test(credential,
            procurement_source_id: socket.assigns.credential_dialog.procurement_source_id
          )

        {:noreply,
         socket
         |> reload_source()
         |> clear_credential_form()
         |> put_flash(
           flash_kind_for_credential_test(test_result),
           credential_save_message(credential, test_result)
         )}

      {:error, form} ->
        {:noreply, assign(socket, :credential_form, to_form(form))}
    end
  end

  @impl true
  def handle_event("refresh_bidnet_session", _params, socket) do
    case Procurement.refresh_bidnet_source_session(socket.assigns.source.procurement_source,
           actor: socket.assigns.current_user
         ) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> reload_source()
         |> put_flash(:info, "BidNet browser session refreshed.")}

      {:error, %{reason: reason}} ->
        {:noreply,
         socket
         |> reload_source()
         |> put_flash(:error, "Could not refresh BidNet session: #{reason}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> reload_source()
         |> put_flash(:error, "Could not refresh BidNet session: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("apply_playbook", %{"playbook_id" => playbook_id}, socket) do
    %{procurement_source: %{id: procurement_source_id}} = socket.assigns.source

    case Operations.apply_playbook(
           %{playbook_id: playbook_id, procurement_source_id: procurement_source_id},
           actor: socket.assigns.current_user
         ) do
      {:ok, run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Applied playbook: #{run.playbook_name}")
         |> assign_playbook_context(socket.assigns.source)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not apply playbook: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_info(%{topic: "procurement_source_browser_session:" <> _event}, socket) do
    {:noreply, reload_source(socket)}
  end

  @impl true
  def handle_info(%{topic: "task:procurement_source:" <> _procurement_source_id}, socket) do
    {:noreply,
     socket
     |> assign(
       :related_tasks,
       load_related_tasks(socket.assigns.source, socket.assigns.current_user)
     )
     |> assign_playbook_context(socket.assigns.source)}
  end

  @impl true
  def handle_info(%{topic: "playbook_run:procurement_source:" <> _procurement_source_id}, socket) do
    {:noreply, assign_playbook_context(socket, socket.assigns.source)}
  end

  defp assign_playbook_context(socket, %{procurement_source: %{id: procurement_source_id}}) do
    actor = socket.assigns.current_user

    playbooks =
      case Operations.list_active_playbooks(actor: actor) do
        {:ok, playbooks} -> playbooks
        {:error, _error} -> []
      end

    runs =
      case Operations.list_playbook_runs_for_procurement_source(procurement_source_id,
             actor: actor
           ) do
        {:ok, runs} -> runs
        {:error, error} -> raise "failed to load playbook runs: #{inspect(error)}"
      end

    socket |> assign(:playbooks, playbooks) |> assign(:playbook_runs, runs)
  end

  defp assign_playbook_context(socket, _source),
    do: socket |> assign(:playbooks, []) |> assign(:playbook_runs, [])

  defp load_related_tasks(%{procurement_source: %{id: procurement_source_id}}, actor) do
    case Operations.list_tasks_by_procurement_source(procurement_source_id,
           actor: actor,
           load: [:status_variant, :priority_variant]
         ) do
      {:ok, tasks} -> tasks
      {:error, error} -> raise "failed to load procurement source tasks: #{inspect(error)}"
    end
  end

  defp load_related_tasks(_source, _actor), do: []

  defp new_source_task_path(source) do
    TaskEntry.new_task_path(%{
      title: "Follow up: #{source.name}",
      task_type: :source_cleanup,
      origin_domain: :procurement,
      origin_resource: "procurement_source",
      origin_id: source.procurement_source.id,
      origin_label: source.name,
      origin_url: ~p"/acquisition/sources/#{source}",
      procurement_source_id: source.procurement_source.id,
      return_to: ~p"/acquisition/sources/#{source}"
    })
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="grid gap-1 px-4 py-3 text-sm sm:grid-cols-[10rem_minmax(0,1fr)]">
      <dt class="font-medium text-base-content/55">{@label}</dt>
      <dd class="min-w-0 text-base-content">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp compact_detail(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3">
      <dt class="text-base-content/50">{@label}</dt>
      <dd class="min-w-0 truncate text-right font-medium text-base-content">{@value}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-200/70 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 text-lg font-semibold tabular-nums text-base-content">{@value || 0}</p>
    </div>
    """
  end

  defp load_source(id, actor) do
    Acquisition.get_source(id, actor: actor, load: @source_load)
  end

  defp reload_source(socket) do
    case load_source(socket.assigns.source.id, socket.assigns.current_user) do
      {:ok, source} ->
        socket
        |> assign(:source, source)
        |> assign(:source_credential, credential_for_source(source))
        |> assign(:browser_session, browser_session_for_source(source))

      {:error, _error} ->
        socket
    end
  end

  defp assign_credential_form(socket, source) do
    family = credential_family_for_source(source)
    family_string = credential_family_string(family)
    secret_kind = credential_secret_kind(family_string)
    params = credential_defaults(source, family_string, secret_kind)

    form =
      AshPhoenix.Form.for_create(SourceCredential, :create,
        actor: socket.assigns.current_user,
        domain: Procurement,
        params: params
      )

    socket
    |> assign(:credential_dialog, %{
      source_id: source.id,
      procurement_source_id: procurement_source_id(source),
      source_name: source.name,
      family: family_string,
      family_label: credential_family_label(family_string),
      secret_kind: secret_kind
    })
    |> assign(:credential_form, to_form(form))
  end

  defp clear_credential_form(socket) do
    socket
    |> assign(:credential_dialog, nil)
    |> assign(:credential_form, nil)
  end

  defp credential_defaults(source, family, secret_kind) do
    %{
      "provider" => credential_provider(family),
      "credential_family" => family,
      "scope" => "family",
      "label" => "#{credential_family_label(family)} default",
      "username" => existing_credential_username(family),
      "credential_storage" => "local_encrypted",
      "bitwarden_server_url" => "https://garden.tail6f3b43.ts.net",
      "bitwarden_organization" => "Gnome Garden",
      "bitwarden_collection" => "Procurement Sources",
      "bitwarden_item_name" => credential_family_label(family),
      "bitwarden_item_id" => "",
      "bitwarden_notes" => "",
      "notes" => "Saved from #{source.name}",
      "api_key" => if(secret_kind == :api_key, do: "", else: nil),
      "password" => if(secret_kind == :username_password, do: "", else: nil)
    }
  end

  defp existing_credential_username(family) do
    case Procurement.list_active_source_credentials_for_family(family, authorize?: false) do
      {:ok, [%{username: username} | _]} when is_binary(username) -> username
      _ -> nil
    end
  end

  defp credential_for_source(source) do
    family =
      source
      |> credential_family_for_source()
      |> credential_family_string()

    source_id = procurement_source_id(source)

    case Procurement.list_source_credentials(authorize?: false) do
      {:ok, credentials} ->
        credentials
        |> Enum.reject(&(&1.status == :disabled))
        |> Enum.sort_by(&(&1.inserted_at || DateTime.from_unix!(0)), {:desc, DateTime})
        |> Enum.find(fn credential ->
          credential_family_string(credential.credential_family) == family and
            (credential.scope != :source || credential.procurement_source_id == source_id)
        end)

      {:error, _error} ->
        nil
    end
  end

  defp browser_session_for_source(source) do
    with source_id when is_binary(source_id) <- procurement_source_id(source),
         {:ok, [session | _]} <-
           Procurement.list_source_browser_sessions_for_source(source_id, authorize?: false) do
      session
    else
      _ -> nil
    end
  end

  defp credential_action_available?(source) do
    credentials_needed?(source) or credentialed_procurement_source?(source)
  end

  defp credentials_needed?(%{health_status: status})
       when status in [:needs_login, :credentials_pending, :credentials_invalid],
       do: true

  defp credentials_needed?(_source), do: false

  defp credentialed_procurement_source?(%{procurement_source: %{source_type: :sam_gov}}), do: true
  defp credentialed_procurement_source?(%{procurement_source: %{source_type: :bidnet}}), do: true
  defp credentialed_procurement_source?(%{procurement_source: %{requires_login: true}}), do: true
  defp credentialed_procurement_source?(_source), do: false

  defp bidnet_source?(%{procurement_source: %{source_type: :bidnet}}), do: true
  defp bidnet_source?(_source), do: false

  defp browser_session_variant(:valid), do: :success
  defp browser_session_variant(:refreshing), do: :info
  defp browser_session_variant(:invalid), do: :error
  defp browser_session_variant(:expired), do: :warning
  defp browser_session_variant(:disabled), do: :default
  defp browser_session_variant(_status), do: :warning

  defp session_credential_label(%{source_credential_id: credential_id}, %{id: credential_id})
       when is_binary(credential_id),
       do: "Current"

  defp session_credential_label(%{source_credential_id: credential_id}, _credential)
       when is_binary(credential_id),
       do: String.slice(credential_id, 0, 8)

  defp session_credential_label(_session, _credential), do: "Not linked"

  defp credential_storage_label(%{credential_storage: :bitwarden}), do: "Bitwarden"
  defp credential_storage_label(_credential), do: "Gnome Garden encrypted"

  defp bitwarden_item_label(%{bitwarden_item_name: name}) when is_binary(name) and name != "",
    do: name

  defp bitwarden_item_label(%{bitwarden_item_id: id}) when is_binary(id) and id != "",
    do: String.slice(id, 0, 12)

  defp bitwarden_item_label(_credential), do: "Not set"

  defp credential_family_for_source(%{procurement_source: procurement_source})
       when is_map(procurement_source) do
    SourceCredentials.credential_family(procurement_source)
  end

  defp credential_family_for_source(source), do: SourceCredentials.credential_family(source)

  defp credential_family_string(family) when is_atom(family), do: Atom.to_string(family)
  defp credential_family_string(family) when is_binary(family), do: family
  defp credential_family_string(_family), do: "custom"

  defp credential_provider(family)
       when family in ["planetbids", "publicpurchase", "sam_gov", "bidnet"],
       do: family

  defp credential_provider(_family), do: "custom"

  defp credential_secret_kind("sam_gov"), do: :api_key
  defp credential_secret_kind(_family), do: :username_password

  defp procurement_source_id(%{procurement_source: %{id: source_id}}) when is_binary(source_id),
    do: source_id

  defp procurement_source_id(%{procurement_source_id: source_id}) when is_binary(source_id),
    do: source_id

  defp procurement_source_id(_source), do: nil

  defp credential_test_label(%{test_status: :queued}), do: "Test queued"
  defp credential_test_label(%{test_status: :testing}), do: "Testing"
  defp credential_test_label(%{test_status: :verified}), do: "Verified"
  defp credential_test_label(%{test_status: :invalid}), do: "Invalid"
  defp credential_test_label(%{test_status: :manual_required}), do: "Manual verification"
  defp credential_test_label(_credential), do: "Untested"

  defp credential_test_variant(%{test_status: :queued}), do: :info
  defp credential_test_variant(%{test_status: :testing}), do: :info
  defp credential_test_variant(%{test_status: :verified}), do: :success
  defp credential_test_variant(%{test_status: :invalid}), do: :error
  defp credential_test_variant(%{test_status: :manual_required}), do: :warning
  defp credential_test_variant(_credential), do: :default

  defp credential_last_test_at(credential) do
    Map.get(credential, :last_test_completed_at) ||
      Map.get(credential, :last_test_started_at) ||
      Map.get(credential, :last_test_queued_at)
  end

  defp flash_kind_for_credential_test({:ok, _queued}), do: :info
  defp flash_kind_for_credential_test({:error, _error}), do: :error

  defp credential_save_message(credential, {:ok, _queued}) do
    "#{credential_family_label(credential.credential_family)} credentials saved. Test queued."
  end

  defp credential_save_message(credential, {:error, error}) do
    "#{credential_family_label(credential.credential_family)} credentials saved, but the test could not be queued: #{inspect(error)}"
  end

  defp credential_family_label("planetbids"), do: "PlanetBids"
  defp credential_family_label("publicpurchase"), do: "PublicPurchase"
  defp credential_family_label("bidnet"), do: "BidNet"
  defp credential_family_label("sam_gov"), do: "SAM.gov"

  defp credential_family_label(family) when is_atom(family),
    do: family |> Atom.to_string() |> credential_family_label()

  defp credential_family_label(family) when is_binary(family) do
    family
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp credential_family_label(_family), do: "Source"
end
