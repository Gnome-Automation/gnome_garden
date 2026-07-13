defmodule GnomeGardenWeb.Components.Acquisition.ShowSections do
  @moduledoc """
  Smaller sections used by the acquisition finding detail page.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Components.OperationsUI, only: [related_tasks_panel: 1]
  import GnomeGardenWeb.Commercial.Helpers, only: [format_atom: 1, format_datetime: 1]

  attr :finding, :map, required: true

  def finding_header_actions(assigns) do
    ~H"""
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
    """
  end

  attr :research_requests, :list, default: []

  def next_actions_section(assigns) do
    ~H"""
    <.section
      :if={@research_requests != []}
      title="Next Actions"
      description="Queued follow-up work created from acquisition review decisions."
      compact
      body_class="p-0"
    >
      <div class="divide-y divide-base-content/10">
        <div
          :for={request <- @research_requests}
          class="grid gap-3 px-3 py-3 text-sm sm:px-4 lg:grid-cols-[minmax(0,1fr)_14rem]"
        >
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-semibold text-base-content">
                {format_atom(request.research_type)}
              </span>
              <.status_badge status={research_state_variant(request.state)}>
                {format_atom(request.state)}
              </.status_badge>
              <span class="badge badge-outline badge-sm">
                {format_atom(request.priority)}
              </span>
            </div>
            <p class="mt-2 leading-6 text-base-content/70">{request.notes}</p>
          </div>
          <div class="text-xs text-base-content/55 lg:text-right">
            <p class="font-semibold uppercase tracking-[0.14em] text-base-content/40">Due</p>
            <p class="mt-1">{format_datetime(request.due_at)}</p>
          </div>
        </div>
      </div>
    </.section>
    """
  end

  attr :finding, :map, required: true
  attr :related_tasks, :list, default: []

  def related_followups_section(assigns) do
    ~H"""
    <.related_tasks_panel
      tasks={@related_tasks}
      description="Operational follow-up linked to this finding."
      empty_description="Accepted findings that need more work will create tasks here."
      new_task_path={new_finding_task_path(@finding)}
    />
    """
  end

  attr :review_notes_form, :any, required: true

  def review_notes_section(assigns) do
    ~H"""
    <.section
      title="Review Notes"
      description="Fill in the minimum explanation needed to accept or promote this finding without leaving the review page."
    >
      <.form
        for={@review_notes_form}
        id="finding-review-notes-form"
        phx-change="validate_review_notes"
        phx-submit="save_review_notes"
        class="space-y-4"
      >
        <div class="grid gap-4 lg:grid-cols-2">
          <.input
            field={@review_notes_form[:summary]}
            type="textarea"
            label="Finding Summary"
          />
          <.input
            field={@review_notes_form[:work_summary]}
            type="textarea"
            label="Work Summary"
          />
          <div class="lg:col-span-2">
            <.input field={@review_notes_form[:source_url]} label="Source URL" />
          </div>
        </div>

        <div class="flex justify-end">
          <.button variant="primary">Save Review Notes</.button>
        </div>
      </.form>
    </.section>
    """
  end

  defp document_action_label(%{finding_family: :procurement}), do: "Upload Packet"
  defp document_action_label(%{finding_family: :discovery}), do: "Upload Source Material"
  defp document_action_label(_finding), do: "Upload Document"

  defp research_state_variant(:requested), do: :warning
  defp research_state_variant(:in_progress), do: :info
  defp research_state_variant(:complete), do: :success
  defp research_state_variant(:cancelled), do: :default
  defp research_state_variant(_state), do: :default

  defp new_finding_task_path(finding) do
    GnomeGardenWeb.Operations.TaskEntry.new_task_path(%{
      title: "Follow up: #{finding.title}",
      task_type: :review,
      origin_domain: :acquisition,
      origin_resource: "finding",
      origin_id: finding.id,
      origin_label: finding.title,
      origin_url: ~p"/acquisition/findings/#{finding}",
      finding_id: finding.id,
      organization_id: finding.organization_id,
      person_id: finding.person_id,
      return_to: ~p"/acquisition/findings/#{finding}"
    })
  end
end
