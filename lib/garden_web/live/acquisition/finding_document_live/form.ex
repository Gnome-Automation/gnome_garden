defmodule GnomeGardenWeb.Acquisition.FindingDocumentLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Components.AcquisitionUI,
    only: [checklist_rule: 1, context_fact: 1, format_error: 1, packet_type_hint: 1]

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.PromotionRules

  @document_type_options [
    {"Solicitation", :solicitation},
    {"Scope", :scope},
    {"Pricing", :pricing},
    {"Addendum", :addendum},
    {"Intake Note", :intake_note},
    {"Other", :other}
  ]

  @document_role_options [
    {"Supporting", :supporting},
    {"Solicitation", :solicitation},
    {"Scope", :scope},
    {"Pricing", :pricing},
    {"Addendum", :addendum},
    {"Research Note", :research_note},
    {"Other", :other}
  ]

  @max_file_size 25_000_000

  @impl true
  def mount(%{"finding_id" => finding_id}, _session, socket) do
    finding = load_finding!(finding_id, socket.assigns.current_user)
    link_params = default_link_params(finding)
    existing_documents = load_existing_documents(finding.id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:finding, finding)
     |> assign(:page_title, page_title(finding))
     |> assign(:document_noun, document_noun(finding))
     |> assign(:document_noun_plural, document_noun_plural(finding))
     |> assign(:existing_documents, existing_documents)
     |> assign(:existing_document_options, Enum.map(existing_documents, &document_option/1))
     |> assign(:link_params, link_params)
     |> assign(:document_type_options, @document_type_options)
     |> assign(:document_role_options, @document_role_options)
     |> allow_upload(:file,
       accept: :any,
       max_entries: 1,
       max_file_size: @max_file_size
     )
     |> assign_form(%{}, link_params)
     |> assign_existing_link_form(default_existing_link_params(finding))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Acquisition">
        {@page_title}
        <:subtitle>
          Attach durable {@document_noun_plural} to this finding so human review and downstream handoff remain explainable.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/acquisition/findings/#{@finding.id}"}>
            Back
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-5">
          <.form
            for={@form}
            id="finding-document-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-5"
          >
            <.section
              title={"Upload New #{String.capitalize(@document_noun)}"}
              description="Create one durable document record, upload the file once, and link it into this finding."
            >
              <div class="mb-4 grid gap-2 sm:grid-cols-4">
                <.packet_type_hint
                  :for={{label, value} <- promotion_counting_document_types()}
                  label={label}
                  value={value}
                  active={
                    to_string(@form[:document_type].value || default_document_type(@finding)) ==
                      to_string(value)
                  }
                />
              </div>

              <div class="grid grid-cols-1 gap-6 sm:grid-cols-6">
                <div class="sm:col-span-4">
                  <.input field={@form[:title]} label="Title" required />
                </div>
                <div class="sm:col-span-2">
                  <.input
                    field={@form[:document_type]}
                    type="select"
                    label="Document Type"
                    options={@document_type_options}
                  />
                </div>
                <div class="sm:col-span-3">
                  <.input
                    name="finding_document[document_role]"
                    id="finding-document-role"
                    type="select"
                    label="Finding Role"
                    options={@document_role_options}
                    value={@link_params["document_role"]}
                  />
                </div>
                <div class="sm:col-span-3">
                  <.input field={@form[:source_url]} label="Source URL" />
                </div>
                <div class="col-span-full">
                  <.input field={@form[:summary]} type="textarea" label="Document Summary" />
                </div>
                <div class="col-span-full">
                  <.input
                    name="finding_document[notes]"
                    id="finding-document-notes"
                    type="textarea"
                    label="Finding Notes"
                    value={@link_params["notes"]}
                  />
                </div>
                <div class="col-span-full space-y-3">
                  <label
                    class="block text-sm/6 font-medium text-gray-900 dark:text-white"
                    for={@uploads.file.ref}
                  >
                    File
                  </label>
                  <div class="rounded-2xl border border-dashed border-zinc-300 bg-white/70 px-4 py-5 dark:border-white/15 dark:bg-white/[0.03]">
                    <.live_file_input
                      upload={@uploads.file}
                      class="file-input file-input-bordered w-full"
                    />
                    <div :if={@uploads.file.entries != []} class="mt-3 space-y-2">
                      <div
                        :for={entry <- @uploads.file.entries}
                        class="flex items-center justify-between rounded-xl border border-zinc-200 px-3 py-2 text-sm dark:border-white/10"
                      >
                        <div>
                          <p class="font-medium text-base-content">
                            {entry.client_name}
                          </p>
                          <p class="text-xs text-base-content/50">
                            {entry.progress}% uploaded
                          </p>
                        </div>
                        <button
                          type="button"
                          class="text-xs font-semibold uppercase tracking-[0.18em] text-zinc-500 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-white"
                          phx-click="cancel-upload"
                          phx-value-ref={entry.ref}
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                    <p
                      :for={error <- upload_errors(@uploads.file)}
                      class="mt-2 text-sm text-red-600 dark:text-red-300"
                    >
                      {upload_error_to_string(error)}
                    </p>
                    <div :for={entry <- @uploads.file.entries}>
                      <p
                        :for={error <- upload_errors(@uploads.file, entry)}
                        class="mt-2 text-sm text-red-600 dark:text-red-300"
                      >
                        {upload_error_to_string(error)}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </.section>

            <.section body_class="px-4 py-4 sm:px-5">
              <.form_actions
                cancel_path={~p"/acquisition/findings/#{@finding.id}"}
                submit_label={"Upload #{String.capitalize(@document_noun)}"}
              />
            </.section>
          </.form>

          <.form
            for={@existing_link_form}
            id="finding-document-link-form"
            phx-submit="link_existing"
            class="space-y-5"
          >
            <.section
              title={"Link Existing #{String.capitalize(@document_noun)}"}
              description="Reuse durable acquisition material that is already in the system instead of uploading the same file again."
            >
              <div
                :if={Enum.empty?(@existing_documents)}
                class="rounded-2xl border border-dashed border-zinc-300 px-4 py-5 text-sm text-zinc-600 dark:border-white/10 dark:text-zinc-300"
              >
                No reusable {@document_noun_plural} are available yet. Upload a new {@document_noun} above first.
              </div>

              <div
                :if={!Enum.empty?(@existing_documents)}
                class="grid grid-cols-1 gap-6 sm:grid-cols-6"
              >
                <div class="sm:col-span-4">
                  <.input
                    field={@existing_link_form[:document_id]}
                    type="select"
                    label="Existing Document"
                    prompt="Select a document"
                    options={@existing_document_options}
                  />
                </div>
                <div class="sm:col-span-2">
                  <.input
                    field={@existing_link_form[:document_role]}
                    type="select"
                    label="Finding Role"
                    options={@document_role_options}
                  />
                </div>
                <div class="col-span-full">
                  <.input
                    field={@existing_link_form[:notes]}
                    type="textarea"
                    label="Finding Notes"
                  />
                </div>
              </div>
            </.section>

            <.section body_class="px-4 py-4 sm:px-5">
              <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <.link
                  navigate={~p"/acquisition/findings/#{@finding.id}"}
                  class="inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium text-zinc-600 transition hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-300 dark:hover:bg-white/[0.05] dark:hover:text-white"
                >
                  Cancel
                </.link>
                <.button type="submit" disabled={Enum.empty?(@existing_documents)}>
                  Link Existing {String.capitalize(@document_noun)}
                </.button>
              </div>
            </.section>
          </.form>
        </div>

        <aside class="space-y-5">
          <.section title="Finding Context">
            <div class="space-y-3">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/40">
                  Intake Finding
                </p>
                <p class="mt-1 text-sm font-semibold text-base-content">
                  {@finding.title}
                </p>
                <p class="mt-1 text-sm text-base-content/70">
                  {@finding.summary || "No summary captured yet."}
                </p>
              </div>

              <div class="grid gap-2 text-sm">
                <.context_fact
                  label="Program"
                  value={if @finding.program, do: @finding.program.name, else: "No program linked"}
                />
                <.context_fact
                  label="Source"
                  value={if @finding.source, do: @finding.source.name, else: "No source linked"}
                />
                <.context_fact
                  label="Organization"
                  value={
                    if @finding.organization,
                      do: @finding.organization.name,
                      else: "No organization linked"
                  }
                />
                <.context_fact
                  label="Linked Documents"
                  value={Integer.to_string(@finding.document_count || 0)}
                />
              </div>
            </div>
          </.section>

          <.section
            title="Promotion Rules"
            description="Procurement findings need one substantive packet before promotion."
          >
            <div class="space-y-2">
              <.checklist_rule label="Solicitation" />
              <.checklist_rule label="Scope" />
              <.checklist_rule label="Pricing" />
              <.checklist_rule label="Addendum" />
            </div>
          </.section>
        </aside>
      </div>
    </.page>
    """
  end

  @impl true
  def handle_event("validate", params, socket) do
    form_params = Map.get(params, "form", %{})

    link_params =
      normalized_link_params(
        Map.get(params, "finding_document", %{}),
        socket.assigns.finding
      )

    {:noreply, assign_form(socket, form_params, link_params)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  def handle_event("link_existing", %{"link" => params}, socket) do
    existing_link_params = normalized_existing_link_params(params, socket.assigns.finding)

    if blank?(existing_link_params["document_id"]) do
      {:noreply,
       socket
       |> assign_existing_link_form(existing_link_params)
       |> put_flash(:error, "Choose an existing document to link")}
    else
      attrs = %{
        finding_id: socket.assigns.finding.id,
        document_id: existing_link_params["document_id"],
        document_role: existing_link_params["document_role"],
        notes: blank_to_nil(existing_link_params["notes"])
      }

      case Acquisition.link_document_to_finding(attrs, actor: socket.assigns.current_user) do
        {:ok, _finding_document} ->
          {:noreply,
           socket
           |> put_flash(:info, "Existing document linked to the finding")
           |> push_navigate(to: ~p"/acquisition/findings/#{socket.assigns.finding.id}")}

        {:error, error} ->
          {:noreply,
           socket
           |> assign_existing_link_form(existing_link_params)
           |> put_flash(:error, "Could not link document: #{format_error(error)}")}
      end
    end
  end

  @impl true
  def handle_event("save", params, socket) do
    form_params = Map.get(params, "form", %{})

    link_params =
      normalized_link_params(
        Map.get(params, "finding_document", %{}),
        socket.assigns.finding
      )

    case consume_upload(socket) do
      {:ok, upload} ->
        submit_params =
          form_params
          |> normalized_params(link_params, socket.assigns.finding)
          |> Map.put("file", upload)

        result =
          AshPhoenix.Form.submit(socket.assigns.form.source,
            params: submit_params
          )

        cleanup_upload(upload)

        case result do
          {:ok, _document} ->
            {:noreply,
             socket
             |> put_flash(:info, "Document uploaded and linked to the finding")
             |> push_navigate(to: ~p"/acquisition/findings/#{socket.assigns.finding.id}")}

          {:error, form} ->
            {:noreply,
             socket
             |> assign(:link_params, link_params)
             |> assign(:form, to_form(form))
             |> put_flash(:error, "Could not upload document")}
        end

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:link_params, link_params)
         |> put_flash(:error, message)}
    end
  end

  defp assign_form(socket, form_params, link_params) do
    seed_params = normalized_params(form_params, link_params, socket.assigns.finding)

    form =
      Acquisition.Document
      |> AshPhoenix.Form.for_create(:upload_for_finding,
        actor: socket.assigns.current_user,
        domain: Acquisition,
        params: seed_params
      )
      |> AshPhoenix.Form.validate(seed_params)

    socket
    |> assign(:link_params, link_params)
    |> assign(:form, to_form(form))
  end

  defp assign_existing_link_form(socket, params) do
    assign(socket, :existing_link_form, to_form(params, as: :link))
  end

  defp load_finding!(finding_id, actor) do
    Acquisition.get_finding!(
      finding_id,
      actor: actor,
      load: [:program, :source, :organization, :document_count]
    )
  end

  defp load_existing_documents(finding_id, actor) do
    linked_document_ids =
      case Acquisition.list_finding_documents_for_finding(finding_id, actor: actor) do
        {:ok, finding_documents} -> MapSet.new(Enum.map(finding_documents, & &1.document_id))
        {:error, _error} -> MapSet.new()
      end

    case Acquisition.list_documents(
           actor: actor,
           load: [:finding_count],
           query: [sort: [uploaded_at: :desc, inserted_at: :desc]]
         ) do
      {:ok, documents} ->
        Enum.reject(documents, &MapSet.member?(linked_document_ids, &1.id))

      {:error, _error} ->
        []
    end
  end

  defp document_option(document) do
    qualifier =
      if PromotionRules.substantive_procurement_document_type?(document.document_type) do
        "counts for promotion"
      else
        "reference only"
      end

    {"#{document.title} [#{humanize_atom(document.document_type)} · #{qualifier}] (#{document.finding_count} links)",
     document.id}
  end

  defp normalized_params(params, link_params, finding) do
    params
    |> Map.put_new("document_type", default_document_type(finding))
    |> Map.put("finding_id", finding.id)
    |> Map.put("document_role", link_params["document_role"])
    |> Map.put("notes", link_params["notes"])
  end

  defp default_link_params(finding) do
    %{
      "document_role" => default_document_role(finding),
      "notes" => ""
    }
  end

  defp normalized_link_params(params, finding) do
    defaults = default_link_params(finding)

    %{
      "document_role" => Map.get(params, "document_role", defaults["document_role"]),
      "notes" => Map.get(params, "notes", defaults["notes"])
    }
  end

  defp default_existing_link_params(finding) do
    %{
      "document_id" => "",
      "document_role" => default_document_role(finding),
      "notes" => ""
    }
  end

  defp normalized_existing_link_params(params, finding) do
    defaults = default_existing_link_params(finding)

    %{
      "document_id" => Map.get(params, "document_id", defaults["document_id"]),
      "document_role" => Map.get(params, "document_role", defaults["document_role"]),
      "notes" => Map.get(params, "notes", defaults["notes"])
    }
  end

  defp consume_upload(socket) do
    uploads =
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
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
      [] -> {:error, "Upload a document file before saving."}
    end
  end

  defp cleanup_upload(%Plug.Upload{path: path}) do
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

  defp upload_error_to_string(:too_large), do: "File is too large."
  defp upload_error_to_string(:too_many_files), do: "Only one file can be uploaded."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(error), do: inspect(error)

  defp page_title(%{finding_family: :procurement}), do: "Add Procurement Packet"
  defp page_title(%{finding_family: :discovery}), do: "Add Source Material"
  defp page_title(_finding), do: "Add Intake Material"

  defp document_noun(%{finding_family: :procurement}), do: "packet"
  defp document_noun(%{finding_family: :discovery}), do: "source material"
  defp document_noun(_finding), do: "material"

  defp document_noun_plural(%{finding_family: :procurement}), do: "packets"
  defp document_noun_plural(%{finding_family: :discovery}), do: "source materials"
  defp document_noun_plural(_finding), do: "materials"

  defp default_document_type(%{finding_family: :procurement}), do: "solicitation"
  defp default_document_type(%{finding_family: :discovery}), do: "intake_note"
  defp default_document_type(_finding), do: "other"

  defp default_document_role(%{finding_family: :procurement}), do: "solicitation"
  defp default_document_role(%{finding_family: :discovery}), do: "research_note"
  defp default_document_role(_finding), do: "supporting"

  defp promotion_counting_document_types do
    [
      {"Solicitation", :solicitation},
      {"Scope", :scope},
      {"Pricing", :pricing},
      {"Addendum", :addendum}
    ]
  end

  defp humanize_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
  defp blank_to_nil(value) when is_binary(value) and value == "", do: nil
  defp blank_to_nil(value), do: value
end
