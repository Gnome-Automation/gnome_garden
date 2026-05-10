defmodule GnomeGardenWeb.Components.AcquisitionUI do
  @moduledoc """
  Shared acquisition review components.
  """

  use Phoenix.Component

  import GnomeGardenWeb.CoreComponents

  alias GnomeGarden.Acquisition.PromotionRules

  attr :finding, :map, required: true
  attr :id_prefix, :string, required: true
  attr :target_id, :string, default: nil
  attr :compact, :boolean, default: false

  def finding_action_bar(assigns) do
    ~H"""
    <div class={["flex flex-wrap", if(@compact, do: "gap-1.5", else: "gap-2")]}>
      <.review_button
        :if={@finding.status == :new}
        id={action_id(@id_prefix, "start-review", @target_id)}
        action="start_review"
        target_id={@target_id}
        compact={@compact}
        icon="hero-play"
      >
        Start Review
      </.review_button>

      <.review_button
        :if={@finding.status == :reviewing and @finding.acceptance_ready}
        id={action_id(@id_prefix, "accept", @target_id)}
        click="open_dialog"
        action="accept"
        target_id={@target_id}
        compact={@compact}
        icon="hero-check"
      >
        Accept
      </.review_button>

      <.button
        :if={prep_action_path(@finding)}
        id={action_id(@id_prefix, "prep", @target_id)}
        navigate={prep_action_path(@finding)}
        class={button_class(@compact, :neutral)}
      >
        <.icon name={prep_action_icon(@finding)} class={icon_class(@compact)} />
        {prep_action_label(@finding)}
      </.button>

      <.review_button
        :if={
          @finding.status == :accepted and @finding.promotion_ready and
            is_nil(@finding.signal_id)
        }
        id={action_id(@id_prefix, "promote", @target_id)}
        action="promote"
        target_id={@target_id}
        compact={@compact}
        tone={:primary}
        icon="hero-arrow-up-right"
      >
        Promote To Signal
      </.review_button>

      <.review_button
        :if={@finding.status in [:reviewing, :accepted]}
        id={action_id(@id_prefix, "reject", @target_id)}
        click="open_dialog"
        action="reject"
        target_id={@target_id}
        compact={@compact}
        tone={:danger}
        icon="hero-x-mark"
      >
        Reject
      </.review_button>

      <.review_button
        :if={@finding.status in [:reviewing, :accepted]}
        id={action_id(@id_prefix, "suppress", @target_id)}
        click="open_dialog"
        action="suppress"
        target_id={@target_id}
        compact={@compact}
        tone={:warning}
        icon="hero-no-symbol"
      >
        Suppress
      </.review_button>

      <.review_button
        :if={@finding.status in [:reviewing, :accepted]}
        id={action_id(@id_prefix, "park", @target_id)}
        click="open_dialog"
        action="park"
        target_id={@target_id}
        compact={@compact}
        tone={:info}
        icon="hero-pause"
      >
        Park
      </.review_button>

      <.review_button
        :if={show_reopen?(@finding)}
        id={action_id(@id_prefix, "reopen", @target_id)}
        action="reopen"
        target_id={@target_id}
        compact={@compact}
        icon="hero-arrow-path"
      >
        Reopen
      </.review_button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :click, :string, default: "transition"
  attr :action, :string, required: true
  attr :target_id, :string, default: nil
  attr :compact, :boolean, default: false
  attr :tone, :atom, default: :default
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp review_button(assigns) do
    ~H"""
    <.button
      id={@id}
      phx-click={@click}
      phx-value-id={@target_id}
      phx-value-action={@action}
      class={button_class(@compact, @tone)}
    >
      <.icon name={@icon} class={icon_class(@compact)} />
      {render_slot(@inner_block)}
    </.button>
    """
  end

  attr :finding, :map, required: true
  attr :finding_documents, :list, default: []
  attr :discovery_evidence, :list, default: []

  def validation_checklist(assigns) do
    assigns =
      assigns
      |> assign(
        :rows,
        validation_rows(assigns.finding, assigns.finding_documents, assigns.discovery_evidence)
      )

    ~H"""
    <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-5">
      <div
        :for={row <- @rows}
        class={[
          "rounded-lg border px-3 py-3",
          row.ready? &&
            "border-emerald-200 bg-emerald-50/80 dark:border-emerald-400/20 dark:bg-emerald-400/10",
          !row.ready? &&
            "border-zinc-200 bg-zinc-50/80 dark:border-white/10 dark:bg-white/[0.03]"
        ]}
      >
        <div class="flex items-start gap-2">
          <span class={[
            "mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full",
            row.ready? && "bg-emerald-600 text-white dark:bg-emerald-400 dark:text-zinc-950",
            !row.ready? && "bg-zinc-200 text-zinc-600 dark:bg-white/10 dark:text-zinc-300"
          ]}>
            <.icon name={if(row.ready?, do: "hero-check", else: "hero-minus")} class="size-3.5" />
          </span>
          <div class="min-w-0">
            <p class="text-sm font-semibold text-base-content">{row.label}</p>
            <p class="mt-0.5 text-xs leading-5 text-base-content/60">{row.detail}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :blockers, :list, default: []

  def blocker_panel(assigns) do
    ~H"""
    <div class="mt-4 rounded-lg border border-amber-200 bg-amber-50/70 px-4 py-4 dark:border-amber-400/20 dark:bg-amber-400/10">
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-amber-700 dark:text-amber-200">
        {@title}
      </p>
      <p class="mt-2 text-sm text-amber-800 dark:text-amber-100">
        {@description}
      </p>
      <ul class="mt-3 space-y-2 text-sm text-amber-900 dark:text-amber-50">
        <li :for={blocker <- @blockers} class="flex gap-2">
          <.icon
            name="hero-exclamation-triangle"
            class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-300"
          />
          <span>{blocker}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :action_dialog, :any, default: nil
  attr :id_prefix, :string, required: true

  def review_dialogs(assigns) do
    ~H"""
    <dialog
      :if={@action_dialog && @action_dialog.type in [:accept, :reject, :suppress]}
      id={"#{@id_prefix}-review-dialog"}
      class="modal"
      phx-hook="ShowModal"
    >
      <div class="modal-box">
        <h3 class="mb-2 text-lg font-bold">{dialog_heading(@action_dialog)}</h3>
        <p class="mb-4 text-sm text-zinc-500">{@action_dialog.title}</p>
        <form
          id={"#{@id_prefix}-#{@action_dialog.type}-form"}
          phx-submit={"submit_#{@action_dialog.type}"}
        >
          <div class="space-y-3">
            <.input
              :if={@action_dialog.type == :accept}
              name="reason"
              value=""
              label="Why are we accepting this finding?"
              type="textarea"
              placeholder="Explain why this intake is worth keeping and refining."
              required
            />
            <.input
              :if={@action_dialog.type in [:reject, :suppress]}
              name="reason_code"
              value={dialog_default_reason_code(@action_dialog)}
              label="Disposition code"
              type="select"
              prompt={dialog_reason_prompt(@action_dialog)}
              options={dialog_reason_options(@action_dialog)}
            />
            <.input
              :if={@action_dialog.type in [:reject, :suppress]}
              name="reason"
              value=""
              label="Operator note (optional)"
              type="text"
              placeholder="Add specific context for this intake decision"
            />
            <.input
              :if={@action_dialog.type in [:reject, :suppress]}
              name="feedback_scope"
              value={dialog_default_feedback_scope(@action_dialog)}
              label="Teach the search/profile (optional)"
              type="select"
              prompt={dialog_feedback_prompt(@action_dialog)}
              options={dialog_feedback_scope_options(@action_dialog)}
            />
            <.input
              :if={@action_dialog.type in [:reject, :suppress]}
              name="exclude_terms"
              value={@action_dialog.suggested_terms}
              label="Keywords to suppress next time"
              type="text"
              placeholder="e.g. cctv, municipal ERP, generic admin software"
            />
          </div>
          <div class="modal-action">
            <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
            <.button type="submit" variant="primary" phx-disable-with="Saving...">
              {dialog_submit_label(@action_dialog)}
            </.button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="close_dialog">close</button>
      </form>
    </dialog>

    <dialog
      :if={@action_dialog && @action_dialog.type == :park}
      id={"#{@id_prefix}-park-dialog"}
      class="modal"
      phx-hook="ShowModal"
    >
      <div class="modal-box">
        <h3 class="mb-2 text-lg font-bold">Park this finding?</h3>
        <p class="mb-4 text-sm text-zinc-500">{@action_dialog.title}</p>
        <form id={"#{@id_prefix}-park-form"} phx-submit="submit_park">
          <div class="space-y-3">
            <.input
              name="reason"
              value=""
              label="Why are we parking this?"
              type="text"
              placeholder="e.g. Keep watching, timing is not right yet"
            />
            <.input
              :if={@action_dialog.family == :procurement}
              name="research"
              value=""
              label="Research needed (optional)"
              type="textarea"
              placeholder="Capture any follow-up research or capability work needed before this returns."
            />
          </div>
          <div class="modal-action">
            <button type="button" phx-click="close_dialog" class="btn btn-ghost">Cancel</button>
            <.button type="submit" variant="primary" phx-disable-with="Parking...">
              Park Finding
            </.button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="close_dialog">close</button>
      </form>
    </dialog>
    """
  end

  defp validation_rows(finding, finding_documents, discovery_evidence) do
    [
      %{
        label: "Review started",
        ready?: finding.status != :new,
        detail:
          if(finding.status == :new,
            do: "Waiting on first operator pass",
            else: "In human review history"
          )
      },
      %{
        label: "Source credible",
        ready?: source_credible?(finding),
        detail:
          if(source_credible?(finding),
            do: "Source or origin is linked",
            else: "Needs source context"
          )
      },
      %{
        label: "Identity linked",
        ready?: identity_linked?(finding),
        detail:
          if(identity_linked?(finding),
            do: "Organization or person is attached",
            else: "No durable identity yet"
          )
      },
      %{
        label: evidence_label(finding),
        ready?: evidence_ready?(finding, finding_documents, discovery_evidence),
        detail: evidence_detail(finding, finding_documents, discovery_evidence)
      },
      %{
        label: "Promotion ready",
        ready?: finding.promotion_ready,
        detail:
          if(finding.promotion_ready, do: "Can move to commercial review", else: "Still blocked")
      }
    ]
  end

  defp source_credible?(finding) do
    not is_nil(finding.source_id) or not is_nil(finding.program_id) or
      not is_nil(finding.source_url) or not is_nil(finding.source_bid_id) or
      not is_nil(finding.source_discovery_record_id)
  end

  defp identity_linked?(finding) do
    source_discovery_record = Map.get(finding, :source_discovery_record)

    not is_nil(finding.organization_id) or not is_nil(finding.person_id) or
      not is_nil(source_discovery_record && source_discovery_record.organization_id) or
      not is_nil(source_discovery_record && source_discovery_record.contact_person_id)
  end

  defp evidence_label(%{finding_family: :procurement}), do: "Packet attached"
  defp evidence_label(%{finding_family: :discovery}), do: "Evidence attached"
  defp evidence_label(_finding), do: "Material attached"

  defp evidence_ready?(%{finding_family: :procurement}, finding_documents, _evidence) do
    Enum.any?(finding_documents, &substantive_procurement_document?/1)
  end

  defp evidence_ready?(%{finding_family: :discovery}, finding_documents, evidence) do
    finding_documents != [] or evidence != []
  end

  defp evidence_ready?(_finding, finding_documents, evidence),
    do: finding_documents != [] or evidence != []

  defp evidence_detail(%{finding_family: :procurement}, finding_documents, _evidence) do
    if Enum.any?(finding_documents, &substantive_procurement_document?/1),
      do: "Substantive packet is linked",
      else: "Needs solicitation, scope, pricing, or addendum"
  end

  defp evidence_detail(%{finding_family: :discovery}, finding_documents, evidence) do
    if finding_documents != [] or evidence != [],
      do: "Evidence or source material is linked",
      else: "Needs evidence before promotion"
  end

  defp evidence_detail(_finding, finding_documents, evidence) do
    if finding_documents != [] or evidence != [],
      do: "Material is linked",
      else: "Needs support material"
  end

  defp substantive_procurement_document?(%{document: %{document_type: document_type}}),
    do: PromotionRules.substantive_procurement_document_type?(document_type)

  defp substantive_procurement_document?(_finding_document), do: false

  defp prep_action_path(%{
         status: status,
         signal_id: nil,
         finding_family: :procurement,
         id: id
       })
       when status in [:reviewing, :accepted],
       do: "/acquisition/findings/#{id}/documents/new"

  defp prep_action_path(%{
         status: status,
         signal_id: nil,
         finding_family: :discovery,
         id: id
       })
       when status in [:reviewing, :accepted],
       do: "/acquisition/findings/#{id}/evidence/new"

  defp prep_action_path(_finding), do: nil

  defp prep_action_label(%{finding_family: :procurement}), do: "Add Packet"
  defp prep_action_label(%{finding_family: :discovery}), do: "Add Evidence"
  defp prep_action_label(_finding), do: "Add Prep"

  defp prep_action_icon(%{finding_family: :procurement}), do: "hero-document-arrow-up"
  defp prep_action_icon(%{finding_family: :discovery}), do: "hero-document-magnifying-glass"
  defp prep_action_icon(_finding), do: "hero-paper-clip"

  defp show_reopen?(%{status: :parked}), do: true

  defp show_reopen?(%{status: :rejected, source_discovery_record_id: target_id})
       when is_binary(target_id),
       do: true

  defp show_reopen?(%{status: :suppressed, source_discovery_record_id: target_id})
       when is_binary(target_id),
       do: true

  defp show_reopen?(_finding), do: false

  defp action_id(prefix, action, nil), do: "#{prefix}-#{action}"
  defp action_id(prefix, action, target_id), do: "#{prefix}-#{action}-#{target_id}"

  defp button_class(compact, tone) do
    [
      "inline-flex items-center justify-center gap-1.5 rounded-md border text-sm font-semibold shadow-sm transition",
      if(compact, do: "px-2.5 py-1.5 text-xs", else: "px-3 py-2"),
      tone_class(tone)
    ]
  end

  defp icon_class(true), do: "size-3.5"
  defp icon_class(false), do: "size-4"

  defp tone_class(:primary),
    do:
      "border-emerald-600 bg-emerald-600 text-white hover:border-emerald-500 hover:bg-emerald-500 dark:border-emerald-500 dark:bg-emerald-500 dark:hover:border-emerald-400 dark:hover:bg-emerald-400"

  defp tone_class(:danger),
    do:
      "border-rose-200 bg-white text-rose-700 hover:border-rose-300 hover:bg-rose-50 dark:border-rose-400/20 dark:bg-white/[0.03] dark:text-rose-300 dark:hover:border-rose-400/40 dark:hover:bg-rose-500/10"

  defp tone_class(:warning),
    do:
      "border-amber-200 bg-white text-amber-700 hover:border-amber-300 hover:bg-amber-50 dark:border-amber-400/20 dark:bg-white/[0.03] dark:text-amber-300 dark:hover:border-amber-400/40 dark:hover:bg-amber-500/10"

  defp tone_class(:info),
    do:
      "border-sky-200 bg-white text-sky-700 hover:border-sky-300 hover:bg-sky-50 dark:border-sky-400/20 dark:bg-white/[0.03] dark:text-sky-300 dark:hover:border-sky-400/40 dark:hover:bg-sky-500/10"

  defp tone_class(_tone),
    do:
      "border-zinc-300 bg-white text-zinc-800 hover:border-zinc-400 hover:bg-zinc-50 dark:border-white/10 dark:bg-white/[0.04] dark:text-white dark:hover:border-white/20 dark:hover:bg-white/[0.08]"

  defp dialog_heading(%{type: :accept}), do: "Accept this finding?"
  defp dialog_heading(%{type: :reject}), do: "Reject this finding?"
  defp dialog_heading(%{type: :suppress}), do: "Suppress this finding?"

  defp dialog_submit_label(%{type: :accept}), do: "Confirm Accept"
  defp dialog_submit_label(%{type: :reject}), do: "Confirm Reject"
  defp dialog_submit_label(%{type: :suppress}), do: "Confirm Suppress"

  defp dialog_reason_prompt(%{type: :accept}), do: nil
  defp dialog_reason_prompt(%{type: :reject}), do: "Select a disposition..."
  defp dialog_reason_prompt(%{type: :suppress}), do: "Select a suppression reason..."

  defp dialog_feedback_prompt(%{type: :accept}), do: nil
  defp dialog_feedback_prompt(%{type: :reject}), do: "Just reject this finding"
  defp dialog_feedback_prompt(%{type: :suppress}), do: "Just suppress this finding"

  defp dialog_default_reason_code(%{type: :accept}), do: nil

  defp dialog_default_reason_code(%{type: :suppress, family: family})
       when family in [:procurement, :discovery],
       do: "source_noise_or_misclassified"

  defp dialog_default_reason_code(_dialog), do: nil

  defp dialog_default_feedback_scope(%{type: :suppress}), do: "source"
  defp dialog_default_feedback_scope(_dialog), do: nil

  defp dialog_reason_options(%{type: :accept}), do: []

  defp dialog_reason_options(%{family: :procurement}),
    do: GnomeGarden.Procurement.TargetingFeedback.pass_reason_options()

  defp dialog_reason_options(%{family: :discovery}),
    do: GnomeGarden.Commercial.DiscoveryFeedback.reject_reason_options()

  defp dialog_reason_options(_dialog), do: []

  defp dialog_feedback_scope_options(%{type: :accept}), do: []

  defp dialog_feedback_scope_options(%{family: family})
       when family in [:procurement, :discovery] do
    [
      {"Out of scope for us", "out_of_scope"},
      {"Not targeting this type right now", "not_targeting_right_now"},
      {"This source is noisy", "source"}
    ]
  end

  defp dialog_feedback_scope_options(_dialog), do: []
end
