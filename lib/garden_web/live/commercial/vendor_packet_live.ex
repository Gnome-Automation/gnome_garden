defmodule GnomeGardenWeb.Commercial.VendorPacketLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Company.DefaultProfiles
  alias GnomeGarden.Commercial.DefaultVendorOnboardings
  alias GnomeGarden.Company.VendorRegistrationPacket

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Customer Onboarding")
     |> assign(:reject_requirement, nil)
     |> assign(:artifact_requirement, nil)
     |> assign(:artifact_form, artifact_default_form())
     |> assign(:artifact_error, nil)
     |> assign(:reveal_sensitive?, false)
     |> allow_upload(:artifact_file, accept: :any, max_entries: 1, max_file_size: 25_000_000)
     |> load_packet()}
  end

  @impl true
  def handle_event("toggle_sensitive", _params, socket) do
    {:noreply,
     socket
     |> update(:reveal_sensitive?, &(!&1))
     |> load_packet()}
  end

  @impl true
  def handle_event("mark_requirement_sent", %{"id" => id}, socket) do
    requirement = get_requirement!(id)
    onboarding = socket.assigns.onboarding

    {:ok, _requirement} =
      GnomeGarden.Commercial.send_customer_vendor_requirement(requirement, %{
        sent_to_email: onboarding.return_email || "sales@gnomeautomation.com"
      })

    {:noreply, load_packet(socket)}
  end

  @impl true
  def handle_event("accept_requirement", %{"id" => id}, socket) do
    requirement = get_requirement!(id)

    {:ok, _requirement} =
      GnomeGarden.Commercial.accept_customer_vendor_requirement(requirement, %{})

    {:noreply, load_packet(socket)}
  end

  @impl true
  def handle_event("waive_requirement", %{"id" => id}, socket) do
    requirement = get_requirement!(id)

    {:ok, _requirement} =
      GnomeGarden.Commercial.waive_customer_vendor_requirement(requirement, %{})

    {:noreply, load_packet(socket)}
  end

  @impl true
  def handle_event("open_reject_requirement", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, :reject_requirement, Enum.find(socket.assigns.requirements, &(&1.id == id)))}
  end

  @impl true
  def handle_event("close_reject_requirement", _params, socket) do
    {:noreply, assign(socket, :reject_requirement, nil)}
  end

  @impl true
  def handle_event("open_artifact_upload", %{"id" => id}, socket) do
    requirement = Enum.find(socket.assigns.requirements, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:artifact_requirement, requirement)
     |> assign(:artifact_form, artifact_default_form(requirement))
     |> assign(:artifact_error, nil)}
  end

  @impl true
  def handle_event("close_artifact_upload", _params, socket) do
    {:noreply,
     socket
     |> assign(:artifact_requirement, nil)
     |> assign(:artifact_form, artifact_default_form())
     |> assign(:artifact_error, nil)}
  end

  @impl true
  def handle_event("validate_artifact", %{"artifact" => params}, socket) do
    {:noreply, assign(socket, :artifact_form, Map.merge(artifact_default_form(), params))}
  end

  @impl true
  def handle_event("cancel-artifact-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact_file, ref)}
  end

  @impl true
  def handle_event("save_artifact", %{"artifact" => params}, socket) do
    requirement = socket.assigns.artifact_requirement

    case consume_artifact_upload(socket) do
      {:ok, upload} ->
        attrs = artifact_attrs(params, requirement, upload)

        result =
          GnomeGarden.Commercial.create_customer_vendor_requirement_artifact(attrs,
            actor: socket.assigns.current_user
          )

        cleanup_artifact_upload(upload)

        case result do
          {:ok, _artifact} ->
            {:noreply,
             socket
             |> put_flash(:info, "Requirement artifact uploaded.")
             |> assign(:artifact_requirement, nil)
             |> assign(:artifact_form, artifact_default_form())
             |> assign(:artifact_error, nil)
             |> load_packet()}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:artifact_error, error_message(error))
             |> assign(:artifact_form, params)}
        end

      {:error, :no_upload} ->
        {:noreply,
         socket
         |> assign(:artifact_error, "Choose a file to upload.")
         |> assign(:artifact_form, params)}
    end
  end

  @impl true
  def handle_event("populate_artifact", %{"id" => id}, socket) do
    case GnomeGarden.Commercial.populate_customer_vendor_requirement_artifact(id,
           actor: socket.assigns.current_user,
           authorize?: false
         ) do
      {:ok, %{"missing_fields" => []}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Filled draft created.")
         |> load_packet()}

      {:ok, %{"missing_fields" => missing_fields}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Filled draft created. Review missing fields: #{Enum.join(missing_fields, ", ")}."
         )
         |> load_packet()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def handle_event(
        "reject_requirement",
        %{"requirement_id" => id, "rejection_reason" => reason},
        socket
      ) do
    requirement = get_requirement!(id)

    {:ok, _requirement} =
      GnomeGarden.Commercial.reject_customer_vendor_requirement(requirement, %{
        rejection_reason: reason
      })

    {:noreply,
     socket
     |> assign(:reject_requirement, nil)
     |> load_packet()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Commercial">
        Customer Onboarding
        <:subtitle>
          Customer-specific vendor setup requirements, forms, send targets, and packet status.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/company/facts"}>
            Company Facts
          </.button>
          <.button navigate={~p"/commercial/agreements"}>
            Agreements
          </.button>
          <.button
            phx-click="toggle_sensitive"
            variant={if(@reveal_sensitive?, do: "primary", else: nil)}
          >
            {if(@reveal_sensitive?, do: "Hide Sensitive", else: "Reveal Sensitive")}
          </.button>
        </:actions>
      </.page_header>

      <.section title={@onboarding.customer_name} body_class="p-0">
        <div class="grid gap-0 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="space-y-4 p-4">
            <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <.source_item label="Return packet to" value={@onboarding.return_email || "-"} />
              <.source_item label="Invoice inbox" value={@onboarding.invoice_email || "-"} />
              <.source_item label="Terms" value={terms_summary(@onboarding)} />
              <.source_item label="Source" value={source_summary(@onboarding)} />
            </div>

            <div class="space-y-2">
              <div class="flex items-center justify-between gap-3 text-xs font-semibold uppercase tracking-[0.14em] text-base-content/45">
                <span>Packet readiness</span>
                <span>{@packet.ready_count} of {@packet.total_count} ready</span>
              </div>
              <progress
                class="progress progress-success h-2 w-full"
                value={@packet.ready_count}
                max={max(@packet.total_count, 1)}
              >
              </progress>
            </div>
          </div>

          <div class="grid grid-cols-3 border-t border-zinc-200 dark:border-white/10 lg:grid-cols-1 lg:border-t-0 lg:border-l">
            <.packet_stat label="Ready" value={@packet.ready_count} tone="success" />
            <.packet_stat label="Missing" value={@packet.missing_count} tone="warning" />
            <.packet_stat label="Total" value={@packet.total_count} tone="neutral" />
          </div>
        </div>
      </.section>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div class="space-y-4">
          <.section
            title="Requirement Lanes"
            description="Customer-owned tasks for getting Gnome approved and ready to invoice."
            body_class="p-0"
          >
            <div class="divide-y divide-zinc-200 dark:divide-white/10">
              <.requirement_group
                :for={group <- requirement_groups(@requirements)}
                group={group}
              />
            </div>
          </.section>

          <.section
            title="Reusable Gnome Packet Data"
            description="Company facts reused across customer forms; edit these in Company Facts when the source record changes."
            body_class="p-0"
          >
            <div class="divide-y divide-zinc-200 dark:divide-white/10">
              <.packet_section :for={section <- @packet.sections} section={section} />
            </div>
          </.section>
        </div>

        <aside class="space-y-4">
          <.section title="Open Gaps" body_class="p-4">
            <div :if={@packet.missing_count == 0} class="text-sm text-base-content/65">
              No missing packet fields.
            </div>
            <div :if={@packet.missing_count > 0} class="space-y-2">
              <.missing_field_card :for={field <- missing_fields(@packet)} field={field} />
            </div>
          </.section>

          <.section title="Reusable Documents" body_class="p-4">
            <div :if={@company_documents == []} class="text-sm text-base-content/65">
              No reusable company documents have been uploaded yet.
            </div>
            <div :if={@company_documents != []} class="space-y-2">
              <.document_card :for={document <- @company_documents} document={document} />
            </div>
          </.section>

          <.section title="Profile Source" body_class="p-4">
            <div class="space-y-3 text-sm">
              <.source_item label="Profile" value={@packet.profile_name || "-"} />
              <.source_item label="Legal name" value={@packet.legal_name || "-"} />
              <.source_item label="Profile key" value={@packet.profile_key || "-"} />
              <.source_item label="Imported" value={@packet.imported_at || "Not imported"} />
            </div>
          </.section>
        </aside>
      </div>

      <div
        :if={@reject_requirement}
        class="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/45 p-4"
      >
        <div class="w-full max-w-lg rounded-lg border border-zinc-200 bg-white p-5 shadow-xl dark:border-white/10 dark:bg-zinc-950">
          <h2 class="text-base font-semibold text-base-content">Reject requirement</h2>
          <p class="mt-1 text-sm text-base-content/60">{@reject_requirement.title}</p>
          <form id="reject-requirement-form" phx-submit="reject_requirement" class="mt-4 space-y-4">
            <input type="hidden" name="requirement_id" value={@reject_requirement.id} />
            <.input
              type="textarea"
              name="rejection_reason"
              label="Reason"
              value=""
              required
              placeholder="What needs to be corrected?"
            />
            <div class="flex justify-end gap-2">
              <button
                type="button"
                phx-click="close_reject_requirement"
                class="btn btn-ghost"
              >
                Cancel
              </button>
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                Save Rejection
              </.button>
            </div>
          </form>
        </div>
      </div>

      <div
        :if={@artifact_requirement}
        class="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/45 p-4"
      >
        <div class="w-full max-w-lg rounded-lg border border-zinc-200 bg-white p-5 shadow-xl dark:border-white/10 dark:bg-zinc-950">
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="text-base font-semibold text-base-content">Upload requirement artifact</h2>
              <p class="mt-1 text-sm text-base-content/60">{@artifact_requirement.title}</p>
            </div>
            <button
              type="button"
              phx-click="close_artifact_upload"
              class="rounded-md p-2 text-base-content/45 hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <div
            :if={@artifact_error}
            class="mt-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800 dark:border-red-400/20 dark:bg-red-400/10 dark:text-red-100"
          >
            {@artifact_error}
          </div>

          <form
            id="requirement-artifact-form"
            phx-change="validate_artifact"
            phx-submit="save_artifact"
            class="mt-4 space-y-4"
          >
            <.input name="artifact[title]" label="Title" value={@artifact_form["title"]} required />
            <.input
              name="artifact[kind]"
              label="Kind"
              type="select"
              options={artifact_kind_options()}
              value={@artifact_form["kind"]}
            />
            <.input
              name="artifact[notes]"
              label="Notes"
              type="textarea"
              value={@artifact_form["notes"]}
            />

            <div class="space-y-2">
              <label
                class="block text-sm font-medium text-base-content"
                for={@uploads.artifact_file.ref}
              >
                File
              </label>
              <div
                id="requirement-artifact-drop-target"
                class="rounded-lg border border-dashed border-base-content/20 bg-base-200/50 p-4 text-center transition phx-drag:bg-primary/10 phx-drag:border-primary"
                phx-drop-target={@uploads.artifact_file.ref}
              >
                <p class="mb-3 text-sm font-medium text-base-content">
                  Drop the customer form, filled draft, signed copy, or sent PDF here.
                </p>
                <.live_file_input
                  upload={@uploads.artifact_file}
                  class="file-input file-input-bordered w-full"
                />
                <div :if={@uploads.artifact_file.entries != []} class="mt-3 space-y-2">
                  <div
                    :for={entry <- @uploads.artifact_file.entries}
                    class="flex items-center justify-between rounded-lg border border-base-content/10 px-3 py-2 text-sm"
                  >
                    <div>
                      <p class="font-medium text-base-content">{entry.client_name}</p>
                      <p class="text-xs text-base-content/50">{entry.progress}% uploaded</p>
                    </div>
                    <button
                      type="button"
                      class="text-xs font-semibold uppercase text-base-content/50 hover:text-base-content"
                      phx-click="cancel-artifact-upload"
                      phx-value-ref={entry.ref}
                    >
                      Remove
                    </button>
                  </div>
                </div>
                <p
                  :for={error <- upload_errors(@uploads.artifact_file)}
                  class="mt-2 text-sm text-red-600 dark:text-red-300"
                >
                  {upload_error_to_string(error)}
                </p>
                <div :for={entry <- @uploads.artifact_file.entries}>
                  <p
                    :for={error <- upload_errors(@uploads.artifact_file, entry)}
                    class="mt-2 text-sm text-red-600 dark:text-red-300"
                  >
                    {upload_error_to_string(error)}
                  </p>
                </div>
              </div>
            </div>

            <div class="flex justify-end gap-2">
              <button type="button" phx-click="close_artifact_upload" class="btn btn-ghost">
                Cancel
              </button>
              <.button type="submit" variant="primary" phx-disable-with="Uploading...">
                Upload Artifact
              </.button>
            </div>
          </form>
        </div>
      </div>
    </.page>
    """
  end

  attr :group, :map, required: true

  defp requirement_group(assigns) do
    ~H"""
    <div class="p-3 sm:p-4">
      <div class="mb-3 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h3 class="text-sm font-semibold text-base-content">{@group.title}</h3>
          <p class="mt-0.5 text-sm text-base-content/55">{@group.description}</p>
        </div>
        <span class="badge badge-outline badge-sm shrink-0">
          {@group.ready_count}/{@group.total_count} ready
        </span>
      </div>
      <div class="grid gap-3">
        <.requirement_row :for={requirement <- @group.requirements} requirement={requirement} />
      </div>
    </div>
    """
  end

  attr :requirement, :map, required: true

  defp requirement_row(assigns) do
    ~H"""
    <div
      id={"vendor-requirement-#{@requirement.key}"}
      class="grid gap-3 rounded-lg border border-zinc-200 bg-white p-3 text-sm dark:border-white/10 dark:bg-white/[0.03] lg:grid-cols-[minmax(0,1fr)_8rem_18rem] lg:items-start"
    >
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <p class="font-medium text-base-content">{@requirement.title}</p>
          <.status_badge status={requirement_status_variant(@requirement.status)}>
            {requirement_status_label(@requirement.status)}
          </.status_badge>
        </div>
        <p class="mt-1 break-words text-base-content/65">{@requirement.instructions}</p>
        <p :if={@requirement.rejection_reason} class="mt-2 text-xs text-red-700 dark:text-red-200">
          {@requirement.rejection_reason}
        </p>
        <.linked_requirement_document
          :if={@requirement.company_document}
          document={@requirement.company_document}
        />
        <div :if={@requirement.artifacts != []} class="mt-3 space-y-2">
          <.requirement_artifact :for={artifact <- @requirement.artifacts} artifact={artifact} />
        </div>
      </div>
      <div class="text-xs uppercase tracking-[0.14em] text-base-content/45">
        {requirement_type_label(@requirement.requirement_type)}
      </div>
      <div class="flex flex-wrap gap-2 lg:justify-end">
        <.button
          type="button"
          phx-click="open_artifact_upload"
          phx-value-id={@requirement.id}
        >
          <.icon name="hero-arrow-up-tray" class="size-4" /> Upload
        </.button>
        <.button
          :if={@requirement.status in [:ready, :rejected]}
          type="button"
          phx-click="mark_requirement_sent"
          phx-value-id={@requirement.id}
        >
          <.icon name="hero-paper-airplane" class="size-4" /> Mark Sent
        </.button>
        <.button
          :if={@requirement.status in [:sent, :rejected]}
          type="button"
          phx-click="accept_requirement"
          phx-value-id={@requirement.id}
        >
          <.icon name="hero-check" class="size-4" /> Accept
        </.button>
        <.button
          :if={@requirement.status not in [:accepted, :waived]}
          type="button"
          phx-click="open_reject_requirement"
          phx-value-id={@requirement.id}
        >
          <.icon name="hero-x-mark" class="size-4" /> Reject
        </.button>
        <.button
          :if={@requirement.status not in [:accepted, :waived]}
          type="button"
          phx-click="waive_requirement"
          phx-value-id={@requirement.id}
        >
          <.icon name="hero-minus-circle" class="size-4" /> Waive
        </.button>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, required: true

  defp packet_stat(assigns) do
    ~H"""
    <div class={[
      "border-zinc-200 px-3 py-3 text-center dark:border-white/10 sm:px-4 lg:text-left",
      @tone == "success" && "text-emerald-700 dark:text-emerald-200",
      @tone == "warning" && "text-amber-700 dark:text-amber-200",
      @tone == "neutral" && "text-base-content"
    ]}>
      <p class="text-xs font-semibold uppercase tracking-[0.14em] opacity-60">{@label}</p>
      <p class="mt-1 text-2xl font-semibold tabular-nums">{@value}</p>
    </div>
    """
  end

  attr :section, :map, required: true

  defp packet_section(assigns) do
    ~H"""
    <details class="group" open={@section.missing_count > 0}>
      <summary class="flex cursor-pointer list-none items-center justify-between gap-3 px-3 py-3 sm:px-4">
        <div>
          <h3 class="text-sm font-semibold text-base-content">{@section.title}</h3>
          <p class="mt-0.5 text-xs text-base-content/45">
            {@section.ready_count} ready / {@section.missing_count} missing
          </p>
        </div>
        <div class="flex items-center gap-2">
          <span
            :if={@section.missing_count > 0}
            class="badge badge-warning badge-sm"
          >
            {@section.missing_count}
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-4 text-base-content/45 transition group-open:rotate-180"
          />
        </div>
      </summary>
      <div class="divide-y divide-zinc-200 border-t border-zinc-200 dark:divide-white/10 dark:border-white/10">
        <.packet_field :for={field <- @section.fields} field={field} />
      </div>
    </details>
    """
  end

  attr :field, :map, required: true

  defp packet_field(assigns) do
    ~H"""
    <div class="grid gap-2 px-3 py-3 text-sm sm:grid-cols-[12rem_minmax(0,1fr)_8rem] sm:items-start sm:px-4">
      <div class="font-medium text-base-content">{@field.label}</div>
      <div class="min-w-0">
        <p class={[
          "break-words leading-6",
          @field.status == :missing && "text-amber-700 dark:text-amber-200",
          @field.status != :missing && "text-base-content/75"
        ]}>
          {@field.display_value}
        </p>
        <p class="mt-0.5 text-xs text-base-content/40">{@field.path}</p>
      </div>
      <div class="flex flex-wrap gap-1 sm:justify-end">
        <.status_badge status={field_status_variant(@field.status)}>
          {field_status_label(@field.status)}
        </.status_badge>
        <span :if={@field.sensitive?} class="badge badge-outline badge-xs">Sensitive</span>
      </div>
    </div>
    """
  end

  attr :field, :map, required: true

  defp missing_field_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 dark:border-amber-400/20 dark:bg-amber-400/10 dark:text-amber-100">
      <p class="font-medium">{@field.label}</p>
      <p class="mt-0.5 text-xs opacity-75">{@field.path}</p>
    </div>
    """
  end

  attr :artifact, :map, required: true

  defp requirement_artifact(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/50 px-3 py-2">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/45">
            {artifact_kind_label(@artifact.kind)}
          </p>
          <p class="mt-0.5 truncate text-sm font-medium text-base-content">
            {@artifact.title}
          </p>
          <p class="mt-0.5 text-xs text-base-content/50">
            {artifact_status_label(@artifact.status)}
          </p>
          <p :if={@artifact.notes} class="mt-1 text-xs text-base-content/60">
            {@artifact.notes}
          </p>
          <div :if={artifact_missing_fields(@artifact) != []} class="mt-2 flex flex-wrap gap-1">
            <span
              :for={field <- artifact_missing_fields(@artifact)}
              class="rounded-full bg-amber-100 px-2 py-0.5 text-[0.68rem] font-medium text-amber-900 dark:bg-amber-400/15 dark:text-amber-100"
            >
              {humanize_atom(field)}
            </span>
          </div>
        </div>
        <.link
          :if={@artifact.file_url}
          href={@artifact.file_url}
          target="_blank"
          class="inline-flex items-center justify-center rounded-md border border-base-content/10 px-3 py-2 text-xs font-semibold text-base-content/70 transition hover:bg-base-100 hover:text-base-content"
        >
          Open File
        </.link>
        <.button
          :if={@artifact.kind == :source_form}
          type="button"
          phx-click="populate_artifact"
          phx-value-id={@artifact.id}
        >
          <.icon name="hero-document-check" class="size-4" /> Populate
        </.button>
      </div>
    </div>
    """
  end

  attr :document, :map, required: true

  defp linked_requirement_document(assigns) do
    ~H"""
    <div class="mt-3 rounded-lg border border-base-content/10 bg-base-200/60 px-3 py-2">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/45">
            Linked company document
          </p>
          <p class="mt-0.5 truncate text-sm font-medium text-base-content">
            {@document.title}
          </p>
          <p class="mt-0.5 text-xs text-base-content/50">
            {document_kind_label(@document.kind)} / {document_status_label(@document.status)}
          </p>
        </div>
        <.link
          :if={@document.file_url}
          href={@document.file_url}
          target="_blank"
          class="inline-flex items-center justify-center rounded-md border border-base-content/10 px-3 py-2 text-xs font-semibold text-base-content/70 transition hover:bg-base-100 hover:text-base-content"
        >
          Open File
        </.link>
      </div>
    </div>
    """
  end

  defp document_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 px-3 py-2 text-sm dark:border-white/10">
      <div class="flex items-start justify-between gap-2">
        <div>
          <p class="font-medium text-base-content">{@document.title}</p>
          <p class="mt-0.5 text-xs text-base-content/45">
            {document_kind_label(@document.kind)}
          </p>
        </div>
        <.status_badge status={requirement_status_variant(@document.status)}>
          {document_status_label(@document.status)}
        </.status_badge>
      </div>
      <.link
        :if={@document.file_url}
        href={@document.file_url}
        target="_blank"
        class="mt-2 inline-flex items-center justify-center rounded-md border border-base-content/10 px-3 py-2 text-xs font-semibold text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
      >
        Open File
      </.link>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp source_item(assigns) do
    ~H"""
    <div>
      <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/45">{@label}</p>
      <p class="mt-0.5 break-words text-base-content/75">{@value}</p>
    </div>
    """
  end

  defp load_packet(socket) do
    profile = DefaultProfiles.ensure_default().profile
    %{onboarding: onboarding} = DefaultVendorOnboardings.ensure_polypeptide()

    {:ok, company_documents} =
      GnomeGarden.Company.list_company_documents_for_profile(profile.id)

    {:ok, requirements} =
      GnomeGarden.Commercial.list_customer_vendor_requirements_for_onboarding(onboarding.id)

    assign(
      socket,
      :packet,
      VendorRegistrationPacket.build(profile, reveal_sensitive?: socket.assigns.reveal_sensitive?)
    )
    |> assign(:onboarding, onboarding)
    |> assign(:requirements, requirements)
    |> assign(:company_documents, company_documents)
  end

  defp artifact_default_form(nil), do: artifact_default_form()

  defp artifact_default_form(requirement) do
    %{
      "title" => "#{requirement.title} source form",
      "kind" => "source_form",
      "notes" => ""
    }
  end

  defp artifact_default_form do
    %{"kind" => "source_form", "notes" => ""}
  end

  defp artifact_kind_options do
    [
      {"Source form", :source_form},
      {"Extracted text", :extracted_text},
      {"Filled DOCX", :filled_docx},
      {"Signed DOCX", :signed_docx},
      {"Approved PDF", :approved_pdf},
      {"Sent copy", :sent_copy},
      {"Supporting", :supporting}
    ]
  end

  defp artifact_attrs(params, requirement, upload) do
    title = blank_to_nil(params["title"]) || "#{requirement.title} artifact"

    %{
      customer_vendor_requirement_id: requirement.id,
      title: title,
      kind: atom_param(params["kind"], :source_form),
      notes: blank_to_nil(params["notes"]),
      metadata: %{
        "uploaded_from" => "vendor_onboarding",
        "customer_vendor_requirement_key" => requirement.key
      },
      file: upload
    }
  end

  defp consume_artifact_upload(socket) do
    uploads =
      consume_uploaded_entries(socket, :artifact_file, fn %{path: path}, entry ->
        preserved_path =
          Path.join(
            System.tmp_dir!(),
            "#{Ecto.UUID.generate()}-#{sanitize_filename(entry.client_name)}"
          )

        File.cp!(path, preserved_path)

        {:ok,
         %Plug.Upload{
           path: preserved_path,
           filename: entry.client_name,
           content_type: entry.client_type
         }}
      end)

    case uploads do
      [upload | _rest] -> {:ok, upload}
      [] -> {:error, :no_upload}
    end
  end

  defp cleanup_artifact_upload(%Plug.Upload{path: path}) do
    File.rm(path)
    :ok
  end

  defp sanitize_filename(filename) do
    filename
    |> String.replace(~r/[^a-zA-Z0-9._-]/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "upload"
      safe -> safe
    end
  end

  defp atom_param(value, _default) when is_binary(value) and value != "",
    do: String.to_existing_atom(value)

  defp atom_param(value, _default) when is_atom(value), do: value
  defp atom_param(_value, default), do: default

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp missing_fields(packet) do
    packet.sections
    |> Enum.flat_map(& &1.fields)
    |> Enum.filter(&(&1.status == :missing))
  end

  defp requirement_groups(requirements) do
    [
      %{
        key: :customer_forms,
        title: "Customer Forms",
        description: "PolyPeptide-owned forms, signatures, and return instructions.",
        types: [:signature, :supplier_code]
      },
      %{
        key: :gnome_records,
        title: "Gnome Records",
        description: "Reusable company documents and facts that satisfy customer requests.",
        types: [:tax_document, :banking_document, :company_fact]
      },
      %{
        key: :commercial_terms,
        title: "Terms & Invoicing",
        description: "Payment terms, delivery terms, invoice inbox, and invoice content rules.",
        types: [:terms, :invoice_instruction]
      },
      %{
        key: :other,
        title: "Other",
        description: "Requirements that do not fit the standard onboarding lanes yet.",
        types: [:other]
      }
    ]
    |> Enum.map(fn group ->
      group_requirements =
        Enum.filter(requirements, &(&1.requirement_type in group.types))

      group
      |> Map.put(:requirements, group_requirements)
      |> Map.put(:total_count, length(group_requirements))
      |> Map.put(:ready_count, Enum.count(group_requirements, &ready_requirement?/1))
    end)
    |> Enum.reject(&(&1.total_count == 0))
  end

  defp ready_requirement?(requirement) do
    requirement.status in [:ready, :sent, :accepted, :waived]
  end

  defp terms_summary(onboarding) do
    [onboarding.payment_terms, onboarding.delivery_terms, onboarding.currency]
    |> Enum.reject(&is_nil_or_blank?/1)
    |> case do
      [] -> "-"
      parts -> Enum.join(parts, " / ")
    end
  end

  defp source_summary(onboarding) do
    onboarding.metadata
    |> Kernel.||(%{})
    |> Map.get("source")
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> onboarding.customer_name || "-"
    end
  end

  defp is_nil_or_blank?(value), do: is_nil(value) or value == ""

  defp field_status_variant(:ready), do: :success
  defp field_status_variant(:not_applicable), do: :default
  defp field_status_variant(:missing), do: :warning

  defp field_status_label(:ready), do: "Ready"
  defp field_status_label(:not_applicable), do: "N/A"
  defp field_status_label(:missing), do: "Missing"

  defp get_requirement!(id) do
    {:ok, requirement} = GnomeGarden.Commercial.get_customer_vendor_requirement(id)
    requirement
  end

  defp requirement_status_variant(:missing), do: :warning
  defp requirement_status_variant(:ready), do: :info
  defp requirement_status_variant(:sent), do: :default
  defp requirement_status_variant(:accepted), do: :success
  defp requirement_status_variant(:rejected), do: :error
  defp requirement_status_variant(:waived), do: :default
  defp requirement_status_variant(:active), do: :success
  defp requirement_status_variant(:draft), do: :warning
  defp requirement_status_variant(:retired), do: :default
  defp requirement_status_variant(:archived), do: :default

  defp requirement_status_label(status), do: status |> Atom.to_string() |> humanize_atom()
  defp document_status_label(status), do: status |> Atom.to_string() |> humanize_atom()
  defp document_kind_label(kind), do: kind |> Atom.to_string() |> humanize_atom()
  defp requirement_type_label(type), do: type |> Atom.to_string() |> humanize_atom()
  defp artifact_kind_label(kind), do: kind |> Atom.to_string() |> humanize_atom()
  defp artifact_status_label(status), do: status |> Atom.to_string() |> humanize_atom()

  defp artifact_missing_fields(%{metadata: %{"fill" => %{"missing_fields" => fields}}})
       when is_list(fields),
       do: fields

  defp artifact_missing_fields(_artifact), do: []

  defp upload_error_to_string(:too_large), do: "File is too large."
  defp upload_error_to_string(:too_many_files), do: "Only one file can be uploaded."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(error), do: "Upload error: #{inspect(error)}"

  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: Exception.message(error)

  defp humanize_atom(value) do
    value
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
