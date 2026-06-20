defmodule GnomeGardenWeb.Acquisition.FindingLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.AcquisitionUI,
    only: [
      finding_review_workbench: 1,
      format_error: 1,
      parse_dialog_action: 1,
      review_dialogs: 1
    ]

  import GnomeGardenWeb.Components.AcquisitionOperatorBrief, only: [operator_brief: 1]

  import GnomeGardenWeb.Components.Acquisition.LinkedDocuments,
    only: [linked_documents_section: 1]

  import GnomeGardenWeb.Components.Acquisition.DiscoveryContext,
    only: [discovery_context_section: 1, discovery_feedback_section: 1, evidence_section: 1]

  import GnomeGardenWeb.Components.Acquisition.IdentityReview, only: [identity_review_section: 1]

  import GnomeGardenWeb.Components.Acquisition.ReviewHistory,
    only: [review_history_section: 1]

  import GnomeGardenWeb.Components.Acquisition.ShowSections,
    only: [
      finding_header_actions: 1,
      next_actions_section: 1,
      related_followups_section: 1,
      review_notes_section: 1
    ]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.ContactEnrichment
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGardenWeb.Operations.TaskPubSub
  alias GnomeGarden.Procurement.TargetingFeedback

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    finding = load_finding!(id, socket.assigns.current_user)

    if connected?(socket) do
      GnomeGardenWeb.Endpoint.subscribe("finding:created")
      GnomeGardenWeb.Endpoint.subscribe("finding:updated")
      GnomeGardenWeb.Endpoint.subscribe("document:created")
      GnomeGardenWeb.Endpoint.subscribe("document:updated")
      GnomeGardenWeb.Endpoint.subscribe("document:destroyed")
      GnomeGardenWeb.Endpoint.subscribe("document_blob:updated")
      GnomeGardenWeb.Endpoint.subscribe("document_blob:destroyed")
      GnomeGardenWeb.Endpoint.subscribe("finding_document:created")
      GnomeGardenWeb.Endpoint.subscribe("finding_document:updated")
      GnomeGardenWeb.Endpoint.subscribe("finding_document:destroyed")
      TaskPubSub.subscribe_related(:finding, finding.id)
    end

    {:ok,
     socket
     |> assign(:page_title, finding.title)
     |> assign(:action_dialog, nil)
     |> assign(:enrichment, nil)
     |> assign_finding_context(finding)}
  end

  @impl true
  def handle_info(%{topic: "finding:" <> _event}, socket) do
    {:noreply, refresh_finding(socket)}
  end

  def handle_info(%{topic: "document:" <> _event}, socket) do
    {:noreply, refresh_finding(socket)}
  end

  def handle_info(%{topic: "document_blob:" <> _event}, socket) do
    {:noreply, refresh_finding(socket)}
  end

  def handle_info(%{topic: "finding_document:" <> _event}, socket) do
    {:noreply, refresh_finding(socket)}
  end

  def handle_info(%{topic: "task:finding:" <> _finding_id}, socket) do
    {:noreply, refresh_finding(socket)}
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
        {:noreply, put_flash(socket, :error, "Could not reopen finding: #{format_error(error)}")}
    end
  end

  def handle_event("open_dialog", params, socket) do
    case params |> dialog_action_param() |> parse_dialog_action() do
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

  def handle_event("validate_review_notes", %{"review_notes" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.review_notes_form, params)
    {:noreply, assign(socket, :review_notes_form, to_form(form))}
  end

  def handle_event("save_review_notes", %{"review_notes" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.review_notes_form, params: params) do
      {:ok, _finding} ->
        {:noreply,
         socket
         |> refresh_finding()
         |> put_flash(:info, "Review notes saved")}

      {:error, form} ->
        {:noreply, assign(socket, :review_notes_form, to_form(form))}
    end
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
        {:noreply, put_flash(socket, :error, "Could not reject finding: #{format_error(error)}")}
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
        {:noreply,
         put_flash(socket, :error, "Could not suppress finding: #{format_error(error)}")}
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
        {:noreply, put_flash(socket, :error, "Could not park finding: #{format_error(error)}")}
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
        {:noreply,
         put_flash(socket, :error, "Could not resolve identity: #{format_error(error)}")}
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
             put_flash(socket, :error, "Could not merge organization: #{format_error(error)}")}
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
            {:noreply,
             put_flash(socket, :error, "Could not merge person: #{format_error(error)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No discovery record linked to this finding")}
    end
  end

  def handle_event("enrich_preview", _params, socket) do
    case enrich_target(socket.assigns.finding) do
      {:finding, finding_id} ->
        result = ContactEnrichment.preview_finding(finding_id, actor: socket.assigns.current_user)
        {:noreply, assign_enrichment(socket, :preview, result)}

      {:org, target} ->
        result = ContactEnrichment.preview(target, actor: socket.assigns.current_user)
        {:noreply, assign_enrichment(socket, :preview, result)}

      :none ->
        {:noreply, put_flash(socket, :error, "No prospect website or analyzed document to extract contacts from.")}
    end
  end

  def handle_event("enrich_confirm", _params, socket) do
    actor = socket.assigns.current_user

    result =
      case enrich_target(socket.assigns.finding) do
        {:finding, finding_id} -> ContactEnrichment.enrich_finding(finding_id, actor: actor)
        {:org, target} -> ContactEnrichment.enrich(target, actor: actor)
        :none -> {:error, :no_source}
      end

    case result do
      {:ok, enriched} ->
        {:noreply,
         socket
         |> refresh_finding()
         |> assign(:enrichment, {:done, enriched})
         |> put_flash(:info, "Saved #{persisted_people_count(enriched)} contact(s).")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Enrichment failed: #{inspect(reason)}")}
    end
  end

  def handle_event("enrich_discard", _params, socket) do
    {:noreply, assign(socket, :enrichment, nil)}
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
          <.finding_header_actions finding={@finding} />
        </:actions>
      </.page_header>

      <.operator_brief finding={@finding} finding_documents={@finding_documents} />

      <.finding_review_workbench
        finding={@finding}
        finding_documents={@finding_documents}
        discovery_evidence={@discovery_evidence}
      />

      <.next_actions_section research_requests={@research_requests} />

      <.related_followups_section finding={@finding} related_tasks={@related_tasks} />

      <.review_notes_section review_notes_form={@review_notes_form} />

      <.linked_documents_section finding={@finding} finding_documents={@finding_documents} />

      <div
        :if={@finding.source_discovery_record}
        class="mt-6 grid gap-6 xl:grid-cols-[1.1fr_0.9fr]"
      >
        <.discovery_context_section discovery_record={@finding.source_discovery_record} />

        <.identity_review_section
          discovery_record={@finding.source_discovery_record}
          identity_review={@discovery_identity_review}
        />
      </div>

      <.discovery_feedback_section
        :if={@finding.source_discovery_record}
        discovery_record={@finding.source_discovery_record}
      />

      <.evidence_section
        discovery_record={@finding.source_discovery_record}
        discovery_evidence={@discovery_evidence}
      />

      <.contact_enrichment_section finding={@finding} enrichment={@enrichment} />

      <.review_history_section review_decisions={@review_decisions} />

      <.review_dialogs action_dialog={@action_dialog} id_prefix="finding-show" />
    </.page>
    """
  end

  attr :finding, :map, required: true
  attr :enrichment, :any, default: nil

  defp contact_enrichment_section(assigns) do
    ~H"""
    <.section title="Contacts" description={enrichment_hint(@finding)}>
      <:actions>
        <.button phx-click="enrich_preview">
          <.icon name="hero-user-plus" class="size-4" /> Find contacts
        </.button>
      </:actions>

      <%= case @enrichment do %>
        <% {:preview, result} -> %>
          <div class="space-y-4">
            <p class="text-sm text-base-content/70">
              Preview only — nothing saved yet.
              <span :if={result.cost && result.cost > 0}>Cost: ${result.cost}.</span>
              <span :if={result.llm.status == :error} class="text-amber-600">
                Name extraction unavailable ({inspect(result.llm.error)}) — only direct emails/phones below.
              </span>
            </p>

            <div :if={result.people == []} class="text-sm text-base-content/60">
              No named people found on the page (often hidden behind a contact form).
            </div>

            <div :for={person <- result.people} class="rounded-lg border border-base-content/10 bg-base-200 px-3 py-2 text-sm">
              <span class="font-medium text-base-content">{person.first_name} {person.last_name}</span>
              <span :if={person.title} class="text-base-content/60">— {person.title}</span>
              <span class="ml-2 text-xs text-base-content/50">conf {person.confidence}</span>
              <div class="text-xs text-base-content/70">
                <span :if={person.email}>{person.email}</span>
                <span :if={person.phone} class="ml-2">{person.phone}</span>
              </div>
            </div>

            <div :if={result.org_contact.emails != [] or result.org_contact.phones != []} class="text-xs text-base-content/60">
              Org-level (unattributed): {Enum.join(result.org_contact.emails ++ result.org_contact.phones, ", ")}
            </div>

            <p :if={result.firmographic} class="text-xs text-base-content/60">
              {result.firmographic.summary}
            </p>

            <div class="flex gap-2">
              <.button phx-click="enrich_confirm" variant="primary">Save contacts</.button>
              <.button phx-click="enrich_discard">Discard</.button>
            </div>
          </div>

        <% {:done, result} -> %>
          <p class="text-sm text-emerald-600">
            Saved {persisted_people_count(result)} contact(s) to this finding. They are inactive (unverified) until you confirm them.
          </p>

        <% _ -> %>
          <p class="text-sm text-base-content/60">
            Extract the contact for this {@finding.finding_family_label} lead. {enrichment_cost_note(@finding)}
          </p>
      <% end %>
    </.section>
    """
  end

  # A procurement RFP names its buyer in the (already analyzed) solicitation
  # document; a discovery/web lead's contacts come from the prospect's site.
  defp enrich_target(%{finding_family: :procurement} = finding), do: {:finding, finding.id}

  defp enrich_target(%{organization: %{website: website} = org})
       when is_binary(website) and website != "" do
    {:org, %{organization_id: org.id, url: website, company: org.name}}
  end

  defp enrich_target(_finding), do: :none

  defp enrichment_hint(%{finding_family: :procurement}),
    do: "Extract the procurement officer from the RFP documents (parsed at ingest) — free, no fetch."

  defp enrichment_hint(_finding),
    do: "Extract contacts from the prospect's website via Exa — a small paid fetch."

  defp enrichment_cost_note(%{finding_family: :procurement}), do: "Free — reads the analyzed RFP text."
  defp enrichment_cost_note(_finding), do: "Costs a small Exa fetch (~$0.006)."

  defp assign_enrichment(socket, :preview, {:ok, result}), do: assign(socket, :enrichment, {:preview, result})

  defp assign_enrichment(socket, :preview, {:error, reason}),
    do: put_flash(socket, :error, "Could not preview contacts: #{inspect(reason)}")

  defp persisted_people_count(%{persisted: %{people: people}}) when is_list(people),
    do: Enum.count(people, fn {tag, _} -> tag in [:created, :existing] end)

  defp persisted_people_count(_result), do: 0

  defp load_finding!(id, actor) do
    Acquisition.get_finding!(
      id,
      actor: actor,
      load: [
        :status_variant,
        :status_label,
        :finding_family_label,
        :finding_family_variant,
        :finding_type_label,
        :confidence_label,
        :confidence_variant,
        :latest_review_reason,
        :latest_review_reason_code,
        :latest_review_feedback_scope,
        :acceptance_ready,
        :acceptance_blockers,
        :promotion_ready,
        :promotion_blockers,
        :document_count,
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

  defp refresh_finding(socket) do
    assign_finding_context(
      socket,
      load_finding!(socket.assigns.finding.id, socket.assigns.current_user)
    )
  end

  defp assign_finding_context(socket, finding) do
    assign(socket,
      finding: finding,
      review_notes_form: build_review_notes_form(finding, socket.assigns.current_user),
      finding_documents: load_finding_documents(finding, socket.assigns.current_user),
      review_decisions: load_review_decisions(finding, socket.assigns.current_user),
      research_requests: load_research_requests(finding, socket.assigns.current_user),
      related_tasks: load_related_tasks(finding, socket.assigns.current_user),
      discovery_identity_review:
        load_discovery_identity_review(finding, socket.assigns.current_user),
      discovery_evidence: load_discovery_evidence(finding, socket.assigns.current_user)
    )
  end

  defp build_review_notes_form(finding, actor) do
    finding
    |> AshPhoenix.Form.for_update(:update,
      actor: actor,
      domain: Acquisition,
      as: "review_notes"
    )
    |> to_form()
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

  defp load_research_requests(%{id: finding_id}, actor) do
    case Acquisition.list_research_requests(
           actor: actor,
           query: [
             filter: [researchable_type: "finding", researchable_id: finding_id],
             sort: [inserted_at: :desc]
           ]
         ) do
      {:ok, requests} -> requests
      {:error, error} -> raise "failed to load finding research requests: #{inspect(error)}"
    end
  end

  defp load_related_tasks(%{id: finding_id}, actor) do
    case Operations.list_tasks_by_finding(finding_id,
           actor: actor,
           load: [:status_variant, :priority_variant]
         ) do
      {:ok, tasks} -> tasks
      {:error, error} -> raise "failed to load finding tasks: #{inspect(error)}"
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

  defp dialog_action_param(params) do
    Map.get(params, "dialog_action") ||
      Map.get(params, "dialog-action") ||
      Map.get(params, "action") ||
      Map.get(params, "value")
  end

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
end
