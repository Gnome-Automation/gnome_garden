defmodule GnomeGardenWeb.Components.Acquisition.LinkedDocuments do
  @moduledoc """
  Linked document section for acquisition finding detail pages.
  """

  use GnomeGardenWeb, :html

  import GnomeGardenWeb.Commercial.Helpers, only: [format_atom: 1]

  alias GnomeGarden.Acquisition.PromotionRules

  attr :finding, :map, required: true
  attr :finding_documents, :list, default: []

  def linked_documents_section(assigns) do
    ~H"""
    <.section
      title="Linked Documents"
      description="Files that make the finding explainable before it crosses into downstream commercial work."
      compact
      body_class="p-0"
    >
      <:actions>
        <.button navigate={~p"/acquisition/findings/#{@finding.id}/documents/new"} variant="primary">
          Upload Document
        </.button>
      </:actions>

      <div
        :if={Enum.empty?(@finding_documents)}
        class="m-3 flex flex-col gap-3 rounded-lg border border-dashed border-zinc-300 px-4 py-5 text-sm text-zinc-600 dark:border-white/10 dark:text-zinc-300 sm:m-4 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex flex-wrap items-center gap-2">
          <.status_badge status={:warning}>Needed</.status_badge>
          <span>No documents linked yet.</span>
        </div>
        <.button navigate={~p"/acquisition/findings/#{@finding.id}/documents/new"}>
          Upload Document
        </.button>
      </div>

      <div
        :if={!Enum.empty?(@finding_documents)}
        class="divide-y divide-zinc-200 dark:divide-white/10"
      >
        <div
          :for={finding_document <- @finding_documents}
          class="grid gap-3 px-3 py-3 sm:px-4 lg:grid-cols-[minmax(0,1fr)_18rem]"
        >
          <div class="min-w-0 space-y-2">
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
              <.status_badge status={finding_document.document_state_variant}>
                {finding_document.document_state_label}
              </.status_badge>
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
            <p :if={finding_document.document.summary} class="text-sm text-base-content/70">
              {finding_document.document.summary}
            </p>
            <.document_analysis_card analysis={document_analysis(finding_document.document)} />
            <p :if={finding_document.notes} class="text-sm text-base-content/70">
              {finding_document.notes}
            </p>
          </div>

          <div class="flex flex-wrap items-start gap-2 lg:justify-end">
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
    </.section>
    """
  end

  defp document_analysis_excerpt(%{file: %{blob: %{metadata: metadata}}}) when is_map(metadata) do
    metadata
    |> metadata_value("document_analysis")
    |> metadata_value("text_excerpt")
    |> case do
      text when is_binary(text) and text != "" -> String.slice(text, 0, 360)
      _ -> nil
    end
  end

  defp document_analysis_excerpt(_document), do: nil

  attr :analysis, :map, default: nil

  defp document_analysis_card(assigns) do
    ~H"""
    <div
      :if={@analysis}
      class="rounded-md border border-base-content/10 bg-base-200/60 px-3 py-3 text-xs leading-5 text-base-content/65"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span class="font-semibold text-base-content">Document Analysis</span>
        <span :if={metadata_value(@analysis, "status")} class="badge badge-outline badge-xs">
          {format_value(metadata_value(@analysis, "status"))}
        </span>
        <span :if={metadata_value(@analysis, "word_count")} class="badge badge-ghost badge-xs">
          {metadata_value(@analysis, "word_count")} words
        </span>
      </div>

      <p :if={metadata_value(@analysis, "scope_summary")} class="mt-2">
        <span class="font-semibold text-base-content/75">Scope:</span>
        {metadata_value(@analysis, "scope_summary")}
      </p>

      <div :if={analysis_list(@analysis, "keyword_hits") != []} class="mt-2 flex flex-wrap gap-1">
        <span
          :for={hit <- analysis_list(@analysis, "keyword_hits")}
          class="badge badge-success badge-xs"
        >
          {hit}
        </span>
      </div>

      <.analysis_list label="Due" values={analysis_list(@analysis, "due_date_mentions")} />
      <.analysis_list
        label="Submission"
        values={analysis_list(@analysis, "submission_instructions")}
      />
      <.analysis_list
        label="Mandatory meeting"
        values={analysis_list(@analysis, "mandatory_meeting")}
      />
      <.analysis_list
        label="Licenses/certs"
        values={analysis_list(@analysis, "required_licenses_certs")}
      />
      <.analysis_list
        label="Bonding/insurance"
        values={analysis_list(@analysis, "bonding_insurance")}
      />
      <.analysis_list label="Red flags" values={analysis_list(@analysis, "red_flags")} />

      <p :if={metadata_value(@analysis, "next_action")} class="mt-2">
        <span class="font-semibold text-base-content/75">Next:</span>
        {metadata_value(@analysis, "next_action")}
      </p>

      <p
        :if={
          document_analysis_excerpt(%{
            file: %{blob: %{metadata: %{"document_analysis" => @analysis}}}
          })
        }
        class="mt-2 line-clamp-3 text-base-content/50"
      >
        {document_analysis_excerpt(%{file: %{blob: %{metadata: %{"document_analysis" => @analysis}}}})}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :values, :list, default: []

  defp analysis_list(assigns) do
    ~H"""
    <div :if={@values != []} class="mt-2">
      <p class="font-semibold text-base-content/75">{@label}</p>
      <ul class="mt-1 space-y-1">
        <li :for={value <- @values} class="flex gap-1.5">
          <span class="text-base-content/35">-</span>
          <span>{value}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp document_analysis(%{file: %{blob: %{metadata: metadata}}}) when is_map(metadata) do
    case metadata_value(metadata, "document_analysis") do
      analysis when is_map(analysis) -> analysis
      _other -> nil
    end
  end

  defp document_analysis(_document), do: nil

  defp analysis_list(analysis, key) when is_map(analysis) do
    analysis
    |> metadata_value(key)
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp analysis_list(_analysis, _key), do: []

  defp metadata_value(nil, _key), do: nil

  defp metadata_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp metadata_value(_value, _key), do: nil

  defp substantive_procurement_document?(%{document: %{document_type: document_type}}),
    do: PromotionRules.substantive_procurement_document_type?(document_type)

  defp substantive_procurement_document?(_finding_document), do: false

  defp format_value(nil), do: "-"

  defp format_value(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
