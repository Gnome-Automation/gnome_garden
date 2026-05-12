defmodule GnomeGardenWeb.Acquisition.FindingLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.AcquisitionUI,
    only: [blocker_panel: 1, finding_action_bar: 1, review_dialogs: 1, validation_checklist: 1]

  import GnomeGardenWeb.Commercial.Helpers, only: [format_atom: 1, format_datetime: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.PromotionRules
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryFeedback
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement.TargetingFeedback

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    finding = load_finding!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, finding.title)
     |> assign(:action_dialog, nil)
     |> assign_finding_context(finding)}
  end

  @impl true
  def handle_event("transition", %{"action" => "start_review"}, socket) do
    with {:ok, _finding} <-
           Acquisition.start_review_for_finding(
             socket.assigns.finding.id,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_finding()
       |> put_flash(:info, "Finding moved into review")}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not start review: #{format_error(error)}")}
    end
  end

  def handle_event("transition", %{"action" => "promote"}, socket) do
    case Acquisition.promote_finding_to_signal(
           socket.assigns.finding.id,
           actor: socket.assigns.current_user
         ) do
      {:ok, %{finding: finding}} when not is_nil(finding.signal_id) ->
        {:noreply,
         socket
         |> refresh_finding()
         |> put_flash(:info, "Promoted finding into commercial review")
         |> push_navigate(to: ~p"/commercial/signals/#{finding.signal_id}")}

      {:ok, _result} ->
        {:noreply, socket |> refresh_finding() |> put_flash(:info, "Promoted finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not promote finding: #{format_error(error)}")}
    end
  end

  def handle_event("transition", %{"action" => "reopen"}, socket) do
    with {:ok, _finding} <-
           Acquisition.reopen_finding_review(
             socket.assigns.finding.id,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_finding()
       |> put_flash(:info, "Reopened finding")}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not reopen finding: #{inspect(error)}")}
    end
  end

  def handle_event("open_dialog", %{"action" => action}, socket) do
    case parse_dialog_action(action) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown acquisition action")}

      dialog_action ->
        {:noreply,
         assign(
           socket,
           :action_dialog,
           build_action_dialog(socket.assigns.finding, dialog_action)
         )}
    end
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :action_dialog, nil)}
  end

  def handle_event("submit_accept", params, socket) do
    case Acquisition.accept_finding_review(
           socket.assigns.finding.id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_finding()
         |> put_flash(:info, "Marked finding as accepted")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not accept finding: #{format_error(error)}")}
    end
  end

  def handle_event("submit_reject", params, socket) do
    case Acquisition.reject_finding_review(
           socket.assigns.finding.id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_finding()
         |> put_flash(:info, "Rejected finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not reject finding: #{inspect(error)}")}
    end
  end

  def handle_event("submit_suppress", params, socket) do
    case Acquisition.suppress_finding_review(
           socket.assigns.finding.id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_finding()
         |> put_flash(:info, "Suppressed finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not suppress finding: #{inspect(error)}")}
    end
  end

  def handle_event("submit_park", params, socket) do
    case Acquisition.park_finding_review(
           socket.assigns.finding.id,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> assign(:action_dialog, nil)
         |> refresh_finding()
         |> put_flash(:info, "Parked finding")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not park finding: #{inspect(error)}")}
    end
  end

  def handle_event("remove_document", %{"id" => id}, socket) do
    with {:ok, finding_document} <-
           Acquisition.get_finding_document(id, actor: socket.assigns.current_user),
         :ok <-
           Acquisition.delete_finding_document(
             finding_document,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_finding()
       |> put_flash(:info, "Removed linked document")}
    else
      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Could not remove linked document: #{format_error(error)}")}
    end
  end

  def handle_event("resolve_identity", params, socket) do
    with %{source_discovery_record: discovery_record} when not is_nil(discovery_record) <-
           socket.assigns.finding,
         attrs when attrs != %{} <- identity_attrs_from_params(params),
         {:ok, _updated_discovery_record} <-
           Commercial.resolve_discovery_record_identity(
             discovery_record,
             attrs,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> refresh_finding()
       |> put_flash(:info, "Discovery record identity updated")}
    else
      %{source_discovery_record: nil} ->
        {:noreply, put_flash(socket, :error, "No discovery record linked to this finding")}

      %{} ->
        {:noreply, put_flash(socket, :error, "Select a candidate before resolving identity")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not resolve identity: #{inspect(error)}")}
    end
  end

  def handle_event("merge_organization", %{"organization_id" => organization_id}, socket) do
    case socket.assigns.finding.source_discovery_record do
      %{organization: nil} ->
        {:noreply, put_flash(socket, :error, "No linked organization to merge")}

      %{organization: source_organization} ->
        case Operations.merge_organization(
               source_organization,
               %{into_organization_id: organization_id},
               actor: socket.assigns.current_user
             ) do
          {:ok, _merged_organization} ->
            {:noreply,
             socket
             |> refresh_finding()
             |> put_flash(:info, "Linked organization merged into selected candidate")}

          {:error, error} ->
            {:noreply,
             put_flash(socket, :error, "Could not merge organization: #{inspect(error)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No discovery record linked to this finding")}
    end
  end

  def handle_event("merge_person", %{"person_id" => person_id}, socket) do
    case socket.assigns.finding.source_discovery_record do
      %{contact_person: nil} ->
        {:noreply, put_flash(socket, :error, "No linked person to merge")}

      %{contact_person: source_person} ->
        case Operations.merge_person(
               source_person,
               %{into_person_id: person_id},
               actor: socket.assigns.current_user
             ) do
          {:ok, _merged_person} ->
            {:noreply,
             socket
             |> refresh_finding()
             |> put_flash(:info, "Linked person merged into selected candidate")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Could not merge person: #{inspect(error)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No discovery record linked to this finding")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        {@finding.title}
        <:subtitle>
          Unified intake record with provenance back to its source lane, origin record, and downstream signal.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings"}>
            Back To Queue
          </.button>
          <.button navigate={~p"/acquisition/findings/#{@finding.id}/documents/new"} variant="primary">
            {document_action_label(@finding)}
          </.button>
          <.button
            :if={@finding.source_discovery_record_id}
            navigate={~p"/acquisition/findings/#{@finding.id}/evidence/new"}
          >
            Add Evidence
          </.button>
          <.button
            :if={@finding.source}
            navigate={
              ~p"/acquisition/findings?family=#{@finding.finding_family}&source_id=#{@finding.source_id}"
            }
          >
            Source Queue
          </.button>
          <.button
            :if={@finding.program}
            navigate={
              ~p"/acquisition/findings?family=#{@finding.finding_family}&program_id=#{@finding.program_id}"
            }
          >
            Program Queue
          </.button>
        </:actions>
      </.page_header>

      <.section
        title="Review Workbench"
        description="Decide from the finding, its source, its proof, and the blockers in one place."
        compact
      >
        <div class="grid gap-5 p-3 sm:p-4 lg:grid-cols-[minmax(0,1fr)_22rem] lg:p-5">
          <div class="min-w-0 space-y-5">
            <div class="space-y-3">
              <div class="flex flex-wrap gap-2">
                <.status_badge status={@finding.status_variant}>
                  {@finding.status |> to_string() |> String.replace("_", " ") |> String.capitalize()}
                </.status_badge>
                <span class="badge badge-info badge-sm">
                  {@finding.finding_family |> to_string() |> String.capitalize()}
                </span>
                <span class="badge badge-outline badge-sm">
                  {@finding.finding_type
                  |> to_string()
                  |> String.replace("_", " ")
                  |> String.capitalize()}
                </span>
                <span :if={@finding.confidence} class={confidence_badge(@finding.confidence)}>
                  {@finding.confidence |> to_string() |> String.capitalize()} confidence
                </span>
              </div>

              <p class="max-w-5xl text-sm leading-6 text-base-content/70">
                {@finding.summary || "No summary captured yet."}
              </p>
            </div>

            <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
              <.workbench_metric label="Fit" value={Integer.to_string(@finding.fit_score || 0)} />
              <.workbench_metric label="Intent" value={Integer.to_string(@finding.intent_score || 0)} />
              <.workbench_metric
                label="Observed"
                value={format_datetime(@finding.observed_at || @finding.inserted_at)}
              />
              <.workbench_metric
                label="Proof"
                value={@finding.proof_label}
              />
            </div>

            <div class="grid gap-3 xl:grid-cols-2">
              <div
                :if={@finding.recommendation}
                class="rounded-lg border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
              >
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                  Recommendation
                </p>
                <p class="mt-2 text-sm leading-6 text-base-content/80">
                  {@finding.recommendation}
                </p>
              </div>

              <div
                :if={@finding.watchouts != []}
                class="rounded-lg border border-amber-200 bg-amber-50/70 px-4 py-4 dark:border-amber-400/20 dark:bg-amber-400/10"
              >
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700 dark:text-amber-200">
                  Watchouts
                </p>
                <div class="mt-2 flex flex-wrap gap-2">
                  <span
                    :for={watchout <- @finding.watchouts}
                    class="badge badge-outline badge-sm border-amber-300 bg-white/80 text-amber-700 dark:border-amber-400/30 dark:bg-transparent dark:text-amber-200"
                  >
                    {watchout}
                  </span>
                </div>
              </div>
            </div>

            <.validation_checklist
              finding={@finding}
              finding_documents={@finding_documents}
              discovery_evidence={@discovery_evidence}
            />

            <.blocker_panel
              :if={@finding.status == :reviewing and not @finding.acceptance_ready}
              title="Acceptance Prep"
              description="Clear these blockers before accepting the finding into the refined intake set."
              blockers={@finding.acceptance_blockers}
            />
            <.blocker_panel
              :if={@finding.status == :accepted and not @finding.promotion_ready}
              title="Promotion Prep"
              description="Promotion stays manual. Clear these blockers before handing the finding into commercial review."
              blockers={@finding.promotion_blockers}
            />
          </div>

          <aside class="space-y-4 rounded-lg border border-zinc-200 bg-zinc-50/70 p-3 dark:border-white/10 dark:bg-white/[0.03]">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                Decision
              </p>
              <.finding_action_bar finding={@finding} id_prefix="finding-show" />
            </div>

            <div class="h-px bg-zinc-200 dark:bg-white/10" />

            <div class="space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                Provenance
              </p>
              <.provenance_item label="Source">
                {if @finding.source, do: @finding.source.name, else: "Direct agent intake"}
              </.provenance_item>
              <.provenance_item label="Program">
                {if @finding.program, do: @finding.program.name, else: "No program linked"}
              </.provenance_item>
              <.provenance_item label="Organization">
                {if @finding.organization,
                  do: @finding.organization.name,
                  else: "No organization linked"}
              </.provenance_item>
              <.provenance_item label="Source URL">
                <a
                  :if={@finding.source_url}
                  href={@finding.source_url}
                  class="break-all text-emerald-700 hover:text-primary"
                >
                  {@finding.source_url}
                </a>
                <span :if={is_nil(@finding.source_url)}>No URL captured</span>
              </.provenance_item>
            </div>

            <div class="flex flex-wrap gap-2 pt-1">
              <.link
                :if={@finding.source_id}
                navigate={
                  ~p"/acquisition/findings?family=#{@finding.finding_family}&source_id=#{@finding.source_id}"
                }
                class="btn btn-sm btn-ghost"
              >
                Open Source Queue
              </.link>
              <.link
                :if={@finding.program_id}
                navigate={
                  ~p"/acquisition/findings?family=#{@finding.finding_family}&program_id=#{@finding.program_id}"
                }
                class="btn btn-sm btn-ghost"
              >
                Open Program Queue
              </.link>
              <.link
                :if={@finding.signal_id}
                navigate={~p"/commercial/signals/#{@finding.signal_id}"}
                class="btn btn-sm btn-ghost"
              >
                Open Signal
              </.link>
              <.link
                :if={@finding.agent_run_id}
                navigate={~p"/console/agents/runs/#{@finding.agent_run_id}"}
                class="btn btn-sm btn-ghost"
              >
                Open Agent Run
              </.link>
            </div>
          </aside>
        </div>
      </.section>

      <.section
        title="Linked Documents"
        description="Durable intake files linked to this finding before it crosses into downstream commercial work."
      >
        <:actions>
          <.button navigate={~p"/acquisition/findings/#{@finding.id}/documents/new"} variant="primary">
            Upload Document
          </.button>
        </:actions>

        <div
          :if={Enum.empty?(@finding_documents)}
          class="flex flex-col gap-3 rounded-2xl border border-dashed border-zinc-300 px-4 py-5 text-sm text-zinc-600 dark:border-white/10 dark:text-zinc-300 sm:flex-row sm:items-center sm:justify-between"
        >
          <span>No documents linked yet.</span>
          <.button navigate={~p"/acquisition/findings/#{@finding.id}/documents/new"}>
            Upload Document
          </.button>
        </div>

        <div :if={!Enum.empty?(@finding_documents)} class="space-y-3">
          <div
            :for={finding_document <- @finding_documents}
            class="rounded-2xl border border-zinc-200 bg-white/80 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div class="space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <p class="text-sm font-semibold text-base-content">
                    {finding_document.document.title}
                  </p>
                  <span class="badge badge-outline badge-sm">
                    {format_atom(finding_document.document_role)}
                  </span>
                  <span class="badge badge-outline badge-sm">
                    {format_atom(finding_document.document.document_type)}
                  </span>
                  <span
                    :if={substantive_procurement_document?(finding_document)}
                    class="badge badge-success badge-sm"
                  >
                    Counts for promotion
                  </span>
                  <span
                    :if={
                      @finding.finding_family == :procurement and
                        not substantive_procurement_document?(finding_document)
                    }
                    class="badge badge-ghost badge-sm"
                  >
                    Reference only
                  </span>
                </div>
                <p
                  :if={finding_document.document.summary}
                  class="text-sm text-base-content/70"
                >
                  {finding_document.document.summary}
                </p>
                <p :if={finding_document.notes} class="text-sm text-base-content/70">
                  {finding_document.notes}
                </p>
              </div>

              <div class="flex flex-wrap gap-2">
                <.link
                  :if={finding_document.document.file_url}
                  href={finding_document.document.file_url}
                  target="_blank"
                  class="btn btn-sm btn-ghost"
                >
                  Open File
                </.link>
                <.link
                  :if={finding_document.document.source_url}
                  href={finding_document.document.source_url}
                  target="_blank"
                  class="btn btn-sm btn-ghost"
                >
                  Open Source
                </.link>
                <.button
                  id={"finding-document-remove-#{finding_document.id}"}
                  phx-click="remove_document"
                  phx-value-id={finding_document.id}
                  class="btn btn-sm btn-ghost text-rose-700 hover:bg-rose-50 hover:text-rose-800 dark:text-rose-300 dark:hover:bg-rose-500/10 dark:hover:text-rose-200"
                >
                  Remove Link
                </.button>
              </div>
            </div>
          </div>
        </div>
      </.section>

      <div
        :if={@finding.source_discovery_record}
        class="mt-6 grid gap-6 xl:grid-cols-[1.1fr_0.9fr]"
      >
        <.section
          title="Discovery Context"
          description="Discovery-origin findings keep their discovery record context here so no separate legacy detail page is needed."
        >
          <div class="grid gap-5 sm:grid-cols-2">
            <.property_item
              label="Website"
              value={@finding.source_discovery_record.website || "-"}
            />
            <.property_item
              label="Domain"
              value={@finding.source_discovery_record.website_domain || "-"}
            />
            <.property_item
              label="Discovery Program"
              value={
                (@finding.source_discovery_record.discovery_program &&
                   @finding.source_discovery_record.discovery_program.name) || "-"
              }
            />
            <.property_item
              label="Linked Organization"
              value={
                (@finding.source_discovery_record.organization &&
                   @finding.source_discovery_record.organization.name) || "-"
              }
            />
            <.property_item
              label="Contact Person"
              value={
                (@finding.source_discovery_record.contact_person &&
                   @finding.source_discovery_record.contact_person.full_name) || "-"
              }
            />
            <.property_item
              label="Evidence Count"
              value={
                Integer.to_string(@finding.source_discovery_record.discovery_evidence_count || 0)
              }
            />
            <.property_item
              label="Latest Observed"
              value={format_datetime(@finding.source_discovery_record.latest_evidence_at)}
            />
            <.property_item
              label="Discovery Record Status"
              value={format_atom(@finding.source_discovery_record.status)}
              badge={@finding.source_discovery_record.status_variant}
            />
          </div>

          <div
            :if={
              discovery_record_icp_matches(@finding.source_discovery_record) != [] or
                discovery_record_risk_flags(@finding.source_discovery_record) != []
            }
            class="mt-5 grid gap-4 sm:grid-cols-2"
          >
            <div
              :if={discovery_record_icp_matches(@finding.source_discovery_record) != []}
              id="finding-show-discovery-icp"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
                Why It Fits
              </p>
              <div class="mt-2 flex flex-wrap gap-1">
                <span
                  :for={match <- discovery_record_icp_matches(@finding.source_discovery_record)}
                  class="badge badge-success badge-sm"
                >
                  {match}
                </span>
              </div>
            </div>

            <div
              :if={discovery_record_risk_flags(@finding.source_discovery_record) != []}
              id="finding-show-discovery-risks"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
                Watchouts
              </p>
              <div class="mt-2 flex flex-wrap gap-1">
                <span
                  :for={flag <- discovery_record_risk_flags(@finding.source_discovery_record)}
                  class="badge badge-outline badge-sm border-amber-300 bg-white/70 text-amber-700 dark:border-amber-400/30 dark:bg-white/[0.03] dark:text-amber-200"
                >
                  {flag}
                </span>
              </div>
            </div>
          </div>
        </.section>

        <.section
          :if={show_identity_review?(@finding.source_discovery_record, @discovery_identity_review)}
          title="Identity Review"
          description="Resolve the canonical organization and person here before this finding becomes owned commercial work."
        >
          <div class="grid gap-6">
            <div class="space-y-4">
              <div class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
                  Organization
                </p>
                <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
                  <%= if @finding.source_discovery_record.organization do %>
                    <div class="flex items-center justify-between gap-3">
                      <div class="space-y-1">
                        <.link
                          navigate={
                            ~p"/operations/organizations/#{@finding.source_discovery_record.organization}"
                          }
                          class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                        >
                          {@finding.source_discovery_record.organization.name}
                        </.link>
                        <p class="text-sm text-base-content/50">
                          {@finding.source_discovery_record.organization.website_domain ||
                            @finding.source_discovery_record.organization.primary_region ||
                            "Linked organization"}
                        </p>
                      </div>
                      <.status_badge status={
                        @finding.source_discovery_record.organization.status_variant
                      }>
                        {format_atom(@finding.source_discovery_record.organization.status)}
                      </.status_badge>
                    </div>
                  <% else %>
                    <p class="text-sm text-base-content/50">
                      No durable organization linked yet.
                    </p>
                  <% end %>
                </div>
              </div>

              <div
                :if={
                  @discovery_identity_review &&
                    @discovery_identity_review.organization_candidates != []
                }
                class="space-y-3"
              >
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
                  Candidate Organizations
                </p>
                <div
                  :for={organization <- @discovery_identity_review.organization_candidates}
                  class="rounded-2xl border border-zinc-200 px-4 py-4 dark:border-white/10"
                >
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="space-y-1">
                      <.link
                        navigate={~p"/operations/organizations/#{organization}"}
                        class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                      >
                        {organization.name}
                      </.link>
                      <p class="text-sm text-base-content/50">
                        {organization.website_domain || organization.primary_region || "No domain"}
                      </p>
                      <p class="text-xs text-base-content/40">
                        {organization.people_count} people · {organization.signal_count} signals
                      </p>
                    </div>
                    <div class="flex flex-wrap gap-2">
                      <.button
                        id={"finding-use-organization-#{organization.id}"}
                        phx-click="resolve_identity"
                        phx-value-organization_id={organization.id}
                        variant="primary"
                      >
                        Use Organization
                      </.button>
                      <.button
                        :if={
                          @finding.source_discovery_record.organization &&
                            @finding.source_discovery_record.organization.id != organization.id
                        }
                        id={"finding-merge-linked-organization-#{organization.id}"}
                        phx-click="merge_organization"
                        phx-value-organization_id={organization.id}
                      >
                        Merge Linked Org
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="space-y-4">
              <div class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
                  Contact Person
                </p>
                <div class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]">
                  <%= if @finding.source_discovery_record.contact_person do %>
                    <div class="flex items-center justify-between gap-3">
                      <div class="space-y-1">
                        <.link
                          navigate={
                            ~p"/operations/people/#{@finding.source_discovery_record.contact_person}"
                          }
                          class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                        >
                          {@finding.source_discovery_record.contact_person.full_name}
                        </.link>
                        <p class="text-sm text-base-content/50">
                          {@finding.source_discovery_record.contact_person.email ||
                            @finding.source_discovery_record.contact_person.phone ||
                            "No direct contact details"}
                        </p>
                      </div>
                      <.status_badge status={
                        @finding.source_discovery_record.contact_person.status_variant
                      }>
                        {format_atom(@finding.source_discovery_record.contact_person.status)}
                      </.status_badge>
                    </div>
                  <% else %>
                    <div class="space-y-1">
                      <p class="text-sm text-base-content/50">
                        No durable contact linked yet.
                      </p>
                      <p
                        :if={
                          @discovery_identity_review && @discovery_identity_review.contact_snapshot
                        }
                        class="text-sm text-base-content/70"
                      >
                        {format_contact_snapshot(@discovery_identity_review.contact_snapshot)}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>

              <div
                :if={@discovery_identity_review && @discovery_identity_review.person_candidates != []}
                class="space-y-3"
              >
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
                  Candidate People
                </p>
                <div
                  :for={person <- @discovery_identity_review.person_candidates}
                  class="rounded-2xl border border-zinc-200 px-4 py-4 dark:border-white/10"
                >
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="space-y-1">
                      <.link
                        navigate={~p"/operations/people/#{person}"}
                        class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                      >
                        {person.full_name}
                      </.link>
                      <p class="text-sm text-base-content/50">
                        {person.email || person.phone || "No direct contact details"}
                      </p>
                      <p class="text-xs text-base-content/40">
                        {candidate_person_organizations(person)}
                      </p>
                    </div>
                    <div class="flex flex-wrap gap-2">
                      <.button
                        id={"finding-use-person-#{person.id}"}
                        phx-click="resolve_identity"
                        phx-value-contact_person_id={person.id}
                        variant="primary"
                      >
                        Use Person
                      </.button>
                      <.button
                        :if={
                          @finding.source_discovery_record.contact_person &&
                            @finding.source_discovery_record.contact_person.id != person.id
                        }
                        id={"finding-merge-linked-person-#{person.id}"}
                        phx-click="merge_person"
                        phx-value-person_id={person.id}
                      >
                        Merge Linked Person
                      </.button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </.section>
      </div>

      <.section
        :if={@finding.source_discovery_record && discovery_feedback(@finding.source_discovery_record)}
        title="Discovery Feedback"
        description="Rejected discovery stays explainable and continues teaching the shared targeting model."
      >
        <div class="grid gap-5 sm:grid-cols-2">
          <.property_item
            label="Disposition"
            value={format_feedback_reason(discovery_feedback(@finding.source_discovery_record))}
          />
          <.property_item
            label="Feedback Scope"
            value={
              format_feedback_scope(
                discovery_feedback(@finding.source_discovery_record)["feedback_scope"]
              )
            }
          />
          <.property_item
            label="Learned Terms"
            value={
              render_feedback_terms(
                discovery_feedback(@finding.source_discovery_record)["exclude_terms"]
              )
            }
          />
          <.property_item
            label="Category"
            value={
              format_feedback_scope(
                discovery_feedback(@finding.source_discovery_record)["source_feedback_category"]
              )
            }
          />
        </div>
      </.section>

      <.section
        :if={@finding.source_discovery_record}
        title="Evidence"
        description="Raw discovery evidence stays attached to the finding so promotion remains explainable."
      >
        <div :if={Enum.empty?(@discovery_evidence)}>
          <.empty_state
            icon="hero-document-magnifying-glass"
            title="No evidence yet"
            description="Discovery runs and operators can still attach evidence before or after review."
          />
        </div>

        <div :if={!Enum.empty?(@discovery_evidence)} class="space-y-3">
          <div
            :for={evidence <- @discovery_evidence}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-2">
                <div class="flex flex-wrap gap-2">
                  <.tag color={:zinc}>{format_atom(evidence.observation_type)}</.tag>
                  <.tag color={:sky}>{format_atom(evidence.source_channel)}</.tag>
                  <.status_badge status={evidence.confidence_variant}>
                    Confidence {evidence.confidence_score}
                  </.status_badge>
                </div>
                <p class="font-medium text-base-content">{evidence.summary}</p>
                <p class="text-xs text-base-content/40">
                  {format_datetime(evidence.observed_at || evidence.inserted_at)}
                </p>
              </div>
              <div class="flex flex-wrap gap-3">
                <.link
                  :if={evidence.source_url}
                  href={evidence.source_url}
                  target="_blank"
                  class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-300"
                >
                  Source
                </.link>
                <.link
                  navigate={~p"/acquisition/evidence/#{evidence.id}/edit"}
                  class="text-sm font-medium text-sky-600 hover:text-sky-500 dark:text-sky-300"
                >
                  Edit
                </.link>
              </div>
            </div>

            <p
              :if={evidence.raw_excerpt}
              class="mt-3 whitespace-pre-wrap text-sm leading-6 text-base-content/70"
            >
              {evidence.raw_excerpt}
            </p>

            <div :if={evidence.evidence_points != []} class="mt-3 flex flex-wrap gap-2">
              <span
                :for={point <- evidence.evidence_points}
                class="badge badge-outline badge-sm border-zinc-200 bg-white/80 text-zinc-700 dark:border-white/10 dark:bg-transparent dark:text-zinc-300"
              >
                {point}
              </span>
            </div>
          </div>
        </div>
      </.section>

      <.section
        title="Review History"
        description="Why operators advanced, rejected, suppressed, parked, reopened, or promoted this finding."
      >
        <div :if={Enum.empty?(@review_decisions)}>
          <.empty_state
            icon="hero-chat-bubble-left-right"
            title="No review history yet"
            description="Decision history will appear here as the finding moves through intake review."
          />
        </div>

        <div :if={!Enum.empty?(@review_decisions)} class="space-y-3">
          <div
            :for={decision <- @review_decisions}
            class="rounded-2xl border border-zinc-200 bg-zinc-50/70 px-4 py-4 dark:border-white/10 dark:bg-white/[0.03]"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <.tag color={decision_tag_color(decision.decision)}>
                    {format_review_decision(decision.decision)}
                  </.tag>
                  <span class="text-xs text-base-content/40">
                    {format_datetime(decision.recorded_at || decision.inserted_at)}
                  </span>
                </div>
                <p :if={decision.reason} class="text-sm text-base-content/80">
                  {decision.reason}
                </p>
                <div class="flex flex-wrap gap-2 text-xs text-base-content/50">
                  <span :if={decision.reason_code}>
                    Code: {format_feedback_scope(decision.reason_code)}
                  </span>
                  <span :if={decision.feedback_scope}>
                    Scope: {format_feedback_scope(decision.feedback_scope)}
                  </span>
                  <span :if={decision.exclude_terms != []}>
                    Terms: {Enum.join(decision.exclude_terms, ", ")}
                  </span>
                  <span :if={decision.metadata["research"]}>
                    Research: {decision.metadata["research"]}
                  </span>
                </div>
                <div
                  :if={decision_snapshot_summary(decision) != []}
                  class="flex flex-wrap gap-2 text-xs text-base-content/50"
                >
                  <span
                    :for={summary <- decision_snapshot_summary(decision)}
                    class="rounded-full bg-white px-2 py-1 ring-1 ring-zinc-200 dark:bg-white/[0.04] dark:ring-white/10"
                  >
                    {summary}
                  </span>
                </div>
              </div>
              <p class="text-xs text-base-content/40">
                {review_actor_name(decision)}
              </p>
            </div>
          </div>
        </div>
      </.section>

      <.review_dialogs action_dialog={@action_dialog} id_prefix="finding-show" />
    </.page>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp provenance_item(assigns) do
    ~H"""
    <div>
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
        {@label}
      </p>
      <div class="mt-1 text-sm text-base-content/80">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp workbench_metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/70 px-3 py-2">
      <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-1 truncate text-sm font-semibold text-base-content">{@value}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :badge, :atom, default: nil

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p :if={is_nil(@badge)} class="text-sm font-medium text-base-content">
        {@value}
      </p>
      <.status_badge :if={@badge} status={@badge}>{@value}</.status_badge>
    </div>
    """
  end

  defp document_action_label(%{finding_family: :procurement}), do: "Upload Packet"
  defp document_action_label(%{finding_family: :discovery}), do: "Upload Source Material"
  defp document_action_label(_finding), do: "Upload Document"

  defp substantive_procurement_document?(%{document: %{document_type: document_type}}),
    do: PromotionRules.substantive_procurement_document_type?(document_type)

  defp substantive_procurement_document?(_finding_document), do: false

  defp load_finding!(id, actor) do
    Acquisition.get_finding!(
      id,
      actor: actor,
      load: [
        :status_variant,
        :acceptance_ready,
        :acceptance_blockers,
        :promotion_ready,
        :promotion_blockers,
        :proof_label,
        :source,
        :program,
        :agent_run,
        :organization,
        :person,
        :signal,
        :source_bid,
        source_discovery_record: [
          :discovery_program,
          :promoted_signal,
          :status_variant,
          :discovery_evidence_count,
          :latest_evidence_at,
          :latest_evidence_summary,
          organization: [:status_variant],
          contact_person: [:status_variant]
        ]
      ]
    )
  end

  defp format_error(%{errors: [error | _]}) do
    Exception.message(error)
  rescue
    _ -> inspect(error)
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)

  defp confidence_badge(:high), do: "badge badge-success badge-sm"
  defp confidence_badge(:medium), do: "badge badge-warning badge-sm"
  defp confidence_badge(:low), do: "badge badge-ghost badge-sm"
  defp confidence_badge(_), do: "badge badge-ghost badge-sm"

  defp refresh_finding(socket) do
    assign_finding_context(
      socket,
      load_finding!(socket.assigns.finding.id, socket.assigns.current_user)
    )
  end

  defp assign_finding_context(socket, finding) do
    assign(socket,
      finding: finding,
      finding_documents: load_finding_documents(finding, socket.assigns.current_user),
      review_decisions: load_review_decisions(finding, socket.assigns.current_user),
      discovery_identity_review:
        load_discovery_identity_review(finding, socket.assigns.current_user),
      discovery_evidence: load_discovery_evidence(finding, socket.assigns.current_user)
    )
  end

  defp load_discovery_identity_review(%{source_discovery_record: nil}, _actor), do: nil

  defp load_discovery_identity_review(%{source_discovery_record: discovery_record}, actor) do
    case Commercial.discovery_record_review_context(discovery_record, actor: actor) do
      {:ok, identity_review} -> identity_review
      {:error, error} -> raise "failed to load discovery identity review: #{inspect(error)}"
    end
  end

  defp load_discovery_evidence(%{source_discovery_record: nil}, _actor), do: []

  defp load_discovery_evidence(%{source_discovery_record_id: target_id}, actor)
       when is_binary(target_id) do
    case Commercial.list_discovery_evidence_for_discovery_record(
           target_id,
           actor: actor,
           load: [:confidence_variant]
         ) do
      {:ok, evidence} -> evidence
      {:error, error} -> raise "failed to load discovery evidence: #{inspect(error)}"
    end
  end

  defp load_finding_documents(%{id: finding_id}, actor) do
    case Acquisition.list_finding_documents_for_finding(finding_id, actor: actor) do
      {:ok, finding_documents} -> finding_documents
      {:error, error} -> raise "failed to load finding documents: #{inspect(error)}"
    end
  end

  defp load_review_decisions(%{id: finding_id}, actor) do
    case Acquisition.list_finding_review_decisions_for_finding(finding_id, actor: actor) do
      {:ok, decisions} -> decisions
      {:error, error} -> raise "failed to load finding review decisions: #{inspect(error)}"
    end
  end

  defp identity_attrs_from_params(params) do
    %{}
    |> maybe_put_identity_attr(:organization_id, Map.get(params, "organization_id"))
    |> maybe_put_identity_attr(:contact_person_id, Map.get(params, "contact_person_id"))
  end

  defp maybe_put_identity_attr(attrs, _key, nil), do: attrs
  defp maybe_put_identity_attr(attrs, _key, ""), do: attrs
  defp maybe_put_identity_attr(attrs, key, value), do: Map.put(attrs, key, value)

  defp parse_dialog_action("accept"), do: :accept
  defp parse_dialog_action("reject"), do: :reject
  defp parse_dialog_action("suppress"), do: :suppress
  defp parse_dialog_action("park"), do: :park
  defp parse_dialog_action(_), do: nil

  defp build_action_dialog(finding, type) do
    %{
      type: type,
      family: finding.finding_family,
      title: finding.title,
      suggested_terms: suggested_terms_for_finding(finding)
    }
  end

  defp suggested_terms_for_finding(%{finding_family: :procurement, source_bid: bid})
       when not is_nil(bid),
       do: TargetingFeedback.suggested_exclude_terms_csv(bid)

  defp suggested_terms_for_finding(%{
         finding_family: :discovery,
         source_discovery_record: discovery_record
       })
       when not is_nil(discovery_record) do
    [discovery_record.industry, discovery_record.website_domain]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp suggested_terms_for_finding(_finding), do: ""

  defp show_identity_review?(_discovery_record, nil), do: false

  defp show_identity_review?(discovery_record, identity_review) do
    not is_nil(discovery_record.contact_person_id) or
      not is_nil(discovery_record.organization_id) or
      not is_nil(identity_review.contact_snapshot) or
      identity_review.organization_candidates != [] or
      identity_review.person_candidates != []
  end

  defp format_contact_snapshot(snapshot) do
    [metadata_value(snapshot, :first_name), metadata_value(snapshot, :last_name)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" ->
        metadata_value(snapshot, :email) || metadata_value(snapshot, :phone) || "Contact snapshot"

      name ->
        [name, metadata_value(snapshot, :title), metadata_value(snapshot, :email)]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" · ")
    end
  end

  defp candidate_person_organizations(person) do
    case person.organizations || [] do
      [] -> "No linked organizations"
      organizations -> organizations |> Enum.map(& &1.name) |> Enum.join(", ")
    end
  end

  defp discovery_feedback(discovery_record) do
    metadata = Map.get(discovery_record, :metadata) || %{}
    metadata["discovery_feedback"]
  end

  defp discovery_record_market_focus(discovery_record) do
    metadata = Map.get(discovery_record, :metadata) || %{}
    Map.get(metadata, "market_focus", %{})
  end

  defp discovery_record_icp_matches(discovery_record) do
    discovery_record
    |> discovery_record_market_focus()
    |> Map.get("icp_matches", [])
    |> List.wrap()
  end

  defp discovery_record_risk_flags(discovery_record) do
    discovery_record
    |> discovery_record_market_focus()
    |> Map.get("risk_flags", [])
    |> List.wrap()
  end

  defp format_feedback_scope(nil), do: "-"

  defp format_feedback_scope(scope) do
    scope
    |> to_string()
    |> String.replace("_", " ")
  end

  defp render_feedback_terms(nil), do: "-"
  defp render_feedback_terms([]), do: "-"
  defp render_feedback_terms(terms), do: Enum.join(List.wrap(terms), ", ")

  defp format_feedback_reason(nil), do: "-"

  defp format_feedback_reason(feedback) when is_map(feedback) do
    reason_code = Map.get(feedback, "reason_code")
    reason = metadata_value(feedback, :reason)
    label = DiscoveryFeedback.reject_reason_label(reason_code)

    if reason in [nil, "", label], do: label, else: "#{label} - #{reason}"
  end

  defp format_feedback_reason(feedback), do: to_string(feedback)

  defp format_review_decision(decision) do
    decision
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp decision_tag_color(:accepted), do: :emerald
  defp decision_tag_color(:promoted), do: :sky
  defp decision_tag_color(:started_review), do: :zinc
  defp decision_tag_color(:reopened), do: :sky
  defp decision_tag_color(:parked), do: :amber
  defp decision_tag_color(:suppressed), do: :amber
  defp decision_tag_color(:rejected), do: :rose
  defp decision_tag_color(_decision), do: :zinc

  defp review_actor_name(%{actor_user: %{full_name: full_name}}) when is_binary(full_name),
    do: full_name

  defp review_actor_name(%{actor_user: %{email: email}}), do: to_string(email)

  defp review_actor_name(%{actor_user_id: actor_user_id}) when is_binary(actor_user_id),
    do: "Operator"

  defp review_actor_name(_decision), do: "System"

  defp decision_snapshot_summary(%{metadata: %{"decision_snapshot" => snapshot}})
       when is_map(snapshot) do
    finding = Map.get(snapshot, "finding", %{})
    readiness = Map.get(snapshot, "readiness", %{})
    material = Map.get(snapshot, "material", %{})

    [
      snapshot_label("State", Map.get(finding, "status")),
      snapshot_label("Fit", Map.get(finding, "fit_score")),
      snapshot_label("Intent", Map.get(finding, "intent_score")),
      snapshot_label("Docs", Map.get(material, "document_count")),
      snapshot_label("Packet Docs", Map.get(material, "promotion_document_count")),
      snapshot_label("Evidence", Map.get(material, "discovery_evidence_count")),
      readiness_label("Accept Ready", Map.get(readiness, "acceptance_ready")),
      readiness_label("Promote Ready", Map.get(readiness, "promotion_ready"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp decision_snapshot_summary(_decision), do: []

  defp snapshot_label(_label, nil), do: nil
  defp snapshot_label(_label, 0), do: nil
  defp snapshot_label(label, value), do: "#{label}: #{format_feedback_scope(value)}"

  defp readiness_label(_label, nil), do: nil
  defp readiness_label(label, true), do: "#{label}: Yes"
  defp readiness_label(label, false), do: "#{label}: No"

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil
end
