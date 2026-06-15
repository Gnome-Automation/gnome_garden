defmodule GnomeGardenWeb.Company.DocumentLive.Index do
  use GnomeGardenWeb, :live_view
  use Cinder.UrlSync

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration

  @kind_options [
    {"W-9", :w9},
    {"Supplier code confirmation", :supplier_code_confirmation},
    {"Insurance certificate", :insurance_certificate},
    {"Capability statement", :capability_statement},
    {"Banking letter", :banking_letter},
    {"Tax certificate", :tax_certificate},
    {"Terms confirmation", :terms_confirmation},
    {"Business license", :business_license},
    {"Other", :other}
  ]

  @status_options [
    {"Draft", :draft},
    {"Active", :active},
    {"Retired", :retired},
    {"Archived", :archived}
  ]

  @max_file_size 25_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Company Documents")
     |> assign(:kind_options, @kind_options)
     |> assign(:status_options, @status_options)
     |> assign(:form_error, nil)
     |> assign(:document_form, default_form())
     |> assign(:edit_form, nil)
     |> assign(:edit_document, nil)
     |> assign(:edit_modal?, false)
     |> assign(:upload_modal?, false)
     |> allow_upload(:file, accept: :any, max_entries: 1, max_file_size: @max_file_size)
     |> load_documents()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = Cinder.UrlSync.handle_params(params, uri, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_upload_modal", _params, socket) do
    {:noreply, assign(socket, :upload_modal?, true)}
  end

  @impl true
  def handle_event("close_upload_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:upload_modal?, false)
     |> assign(:form_error, nil)}
  end

  @impl true
  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    document = Company.get_company_document!(id, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:edit_modal?, true)
     |> assign(:edit_document, document)
     |> assign(:edit_form, document_form(document))
     |> assign(:form_error, nil)}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:edit_modal?, false)
     |> assign(:edit_document, nil)
     |> assign(:edit_form, nil)
     |> assign(:form_error, nil)}
  end

  @impl true
  def handle_event("validate_document", %{"document" => params}, socket) do
    {:noreply, assign(socket, :document_form, Map.merge(default_form(), params))}
  end

  @impl true
  def handle_event("validate_edit_document", %{"document" => params}, socket) do
    {:noreply, assign(socket, :edit_form, Map.merge(socket.assigns.edit_form || %{}, params))}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  @impl true
  def handle_event("save_document", %{"document" => params}, socket) do
    case consume_upload(socket) do
      {:ok, upload} ->
        attrs = document_attrs(params, socket.assigns.profile.id, upload)
        result = Company.create_company_document(attrs, actor: socket.assigns.current_user)
        cleanup_upload(upload)

        case result do
          {:ok, _document} ->
            {:noreply,
             socket
             |> put_flash(:info, "Company document uploaded.")
             |> assign(:form_error, nil)
             |> assign(:upload_modal?, false)
             |> assign(:document_form, default_form())
             |> load_documents()
             |> Cinder.refresh_table("company-documents")}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:form_error, error_message(error))
             |> assign(:document_form, params)}
        end

      {:error, :no_upload} ->
        {:noreply,
         socket
         |> assign(:form_error, "Choose a file to upload.")
         |> assign(:document_form, params)}
    end
  end

  @impl true
  def handle_event("update_document", %{"document" => params}, socket) do
    document = socket.assigns.edit_document

    {attrs, upload} =
      case consume_optional_upload(socket) do
        {:ok, upload} -> {Map.put(document_update_attrs(params, document), :file, upload), upload}
        {:error, :no_upload} -> {document_update_attrs(params, document), nil}
      end

    result = Company.update_company_document(document, attrs, actor: socket.assigns.current_user)
    if upload, do: cleanup_upload(upload)

    case result do
      {:ok, _document} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company document updated.")
         |> assign(:form_error, nil)
         |> assign(:edit_modal?, false)
         |> assign(:edit_document, nil)
         |> assign(:edit_form, nil)
         |> load_documents()
         |> Cinder.refresh_table("company-documents")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:form_error, error_message(error))
         |> assign(:edit_form, params)}
    end
  end

  @impl true
  def handle_event("activate", %{"id" => id}, socket) do
    document = Company.get_company_document!(id, actor: socket.assigns.current_user)

    {:ok, _document} =
      Company.activate_company_document(document, actor: socket.assigns.current_user)

    {:noreply, socket |> load_documents() |> Cinder.refresh_table("company-documents")}
  end

  @impl true
  def handle_event("retire", %{"id" => id}, socket) do
    document = Company.get_company_document!(id, actor: socket.assigns.current_user)

    {:ok, _document} =
      Company.retire_company_document(document, actor: socket.assigns.current_user)

    {:noreply, socket |> load_documents() |> Cinder.refresh_table("company-documents")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Company">
        Documents
        <:subtitle>
          Reusable Gnome-owned files for vendor portals, payee setup, compliance, and customer onboarding.
        </:subtitle>
        <:actions>
          <.button id="open-company-document-upload" phx-click="open_upload_modal" variant="primary">
            Upload Document
          </.button>
        </:actions>
      </.page_header>

      <div
        :if={@form_error}
        class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800 dark:border-red-400/20 dark:bg-red-400/10 dark:text-red-100"
      >
        {@form_error}
      </div>

      <div class="space-y-5">
        <div class="grid grid-cols-3 gap-2 sm:gap-3">
          <.document_stat label="On file" value={length(@documents)} />
          <.document_stat label="Active" value={Enum.count(@documents, &(&1.status == :active))} />
          <.document_stat label="Types" value={document_type_count(@documents)} />
        </div>

        <div class="rounded-lg border border-base-content/10 bg-base-100">
          <Cinder.collection
            id="company-documents"
            query={@document_query}
            actor={@current_user}
            url_state={@url_state}
            theme={GnomeGardenWeb.CinderTheme}
            layout={:grid}
            grid_columns={[xs: 1, xl: 2]}
            page_size={12}
            show_sort={false}
            search={[
              label: "Search documents",
              placeholder: "Search by title, key, or description"
            ]}
            query_opts={[load: [:file_url, file: :blob]]}
            empty_message="No company documents match this search."
          >
            <:col field="title" sort search label="Title" />
            <:col field="key" search label="Key" />
            <:col field="description" search label="Description" />
            <:col
              field="kind"
              sort
              filter={[type: :select, options: @kind_options, prompt: "All types"]}
              label="Type"
            />
            <:col
              field="status"
              sort
              filter={[type: :select, options: @status_options, prompt: "All statuses"]}
              label="Status"
            />
            <:col field="effective_on" sort label="Effective" />
            <:col field="expires_on" sort label="Expires" />

            <:item :let={document}>
              <.document_card document={document} />
            </:item>

            <:empty>
              <.empty_state
                icon="hero-document-text"
                title="No documents found"
                description="Upload reusable company documents such as W-9s, bank letters, insurance certificates, supplier code confirmations, and capability statements."
              >
                <:action>
                  <.button phx-click="open_upload_modal" variant="primary">
                    Upload Document
                  </.button>
                </:action>
              </.empty_state>
            </:empty>
          </Cinder.collection>
        </div>
      </div>

      <.modal
        :if={@upload_modal?}
        id="company-document-upload-modal"
        on_cancel={JS.push("close_upload_modal")}
      >
        <:title>Upload Company Document</:title>
        <div class="space-y-4">
          <p class="text-sm leading-5 text-base-content/65">
            Add a reusable company-owned file. Customer-specific completed forms should stay with the related onboarding record unless they are reusable.
          </p>
          <form
            id="company-document-form"
            phx-change="validate_document"
            phx-submit="save_document"
            class="space-y-4"
          >
            <.input name="document[title]" label="Title" value={@document_form["title"]} required />
            <.input name="document[key]" label="Key" value={@document_form["key"]} />
            <.input
              name="document[kind]"
              label="Kind"
              type="select"
              options={@kind_options}
              value={@document_form["kind"]}
            />
            <.input
              name="document[status]"
              label="Status"
              type="select"
              options={@status_options}
              value={@document_form["status"]}
            />
            <div class="grid gap-4 sm:grid-cols-3 xl:grid-cols-1">
              <.input
                name="document[signed_on]"
                label="Signed on"
                type="date"
                value={@document_form["signed_on"]}
              />
              <.input
                name="document[effective_on]"
                label="Effective on"
                type="date"
                value={@document_form["effective_on"]}
              />
              <.input
                name="document[expires_on]"
                label="Expires on"
                type="date"
                value={@document_form["expires_on"]}
              />
            </div>
            <.input
              name="document[description]"
              label="Description"
              type="textarea"
              value={@document_form["description"]}
            />
            <.input
              name="document[tags]"
              label="Tags"
              value={@document_form["tags"]}
              placeholder="vendor setup, tax, reusable"
            />

            <div class="space-y-2">
              <label class="block text-sm font-medium text-base-content" for={@uploads.file.ref}>
                File
              </label>
              <div
                id="company-document-drop-target"
                class="rounded-lg border border-dashed border-base-content/20 bg-base-200/50 p-4 text-center transition phx-drag:bg-primary/10 phx-drag:border-primary"
                phx-drop-target={@uploads.file.ref}
              >
                <p class="mb-3 text-sm font-medium text-base-content">
                  Drop a file here or choose one from your device.
                </p>
                <.live_file_input
                  upload={@uploads.file}
                  class="file-input file-input-bordered w-full"
                />
                <div :if={@uploads.file.entries != []} class="mt-3 space-y-2">
                  <div
                    :for={entry <- @uploads.file.entries}
                    class="flex items-center justify-between rounded-lg border border-base-content/10 px-3 py-2 text-sm"
                  >
                    <div>
                      <p class="font-medium text-base-content">{entry.client_name}</p>
                      <p class="text-xs text-base-content/50">{entry.progress}% uploaded</p>
                    </div>
                    <button
                      type="button"
                      class="text-xs font-semibold uppercase text-base-content/50 hover:text-base-content"
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

            <div class="flex justify-end">
              <.button type="submit" variant="primary" phx-disable-with="Uploading...">
                Upload Document
              </.button>
            </div>
          </form>
        </div>
      </.modal>

      <.modal
        :if={@edit_modal?}
        id="company-document-edit-modal"
        on_cancel={JS.push("close_edit_modal")}
      >
        <:title>Edit Company Document</:title>
        <div class="space-y-4">
          <p class="text-sm leading-5 text-base-content/65">
            Update the reusable document metadata shown in vendor portals and onboarding packets.
          </p>
          <form
            id="company-document-edit-form"
            phx-change="validate_edit_document"
            phx-submit="update_document"
            class="space-y-4"
          >
            <.input name="document[title]" label="Title" value={@edit_form["title"]} required />
            <.input name="document[key]" label="Key" value={@edit_form["key"]} required />
            <.input
              name="document[kind]"
              label="Kind"
              type="select"
              options={@kind_options}
              value={@edit_form["kind"]}
            />
            <.input
              name="document[status]"
              label="Status"
              type="select"
              options={@status_options}
              value={@edit_form["status"]}
            />
            <div class="grid gap-4 sm:grid-cols-3 xl:grid-cols-1">
              <.input
                name="document[signed_on]"
                label="Signed on"
                type="date"
                value={@edit_form["signed_on"]}
              />
              <.input
                name="document[effective_on]"
                label="Effective on"
                type="date"
                value={@edit_form["effective_on"]}
              />
              <.input
                name="document[expires_on]"
                label="Expires on"
                type="date"
                value={@edit_form["expires_on"]}
              />
            </div>
            <.input
              name="document[description]"
              label="Description"
              type="textarea"
              value={@edit_form["description"]}
            />
            <.input
              name="document[tags]"
              label="Tags"
              value={@edit_form["tags"]}
              placeholder="vendor setup, tax, reusable"
            />

            <div class="space-y-2">
              <label class="block text-sm font-medium text-base-content" for={@uploads.file.ref}>
                Replace file
              </label>
              <div
                id="company-document-replace-drop-target"
                class="rounded-lg border border-dashed border-base-content/20 bg-base-200/50 p-4 text-center transition phx-drag:bg-primary/10 phx-drag:border-primary"
                phx-drop-target={@uploads.file.ref}
              >
                <p class="mb-3 text-sm font-medium text-base-content">
                  Drop a replacement file here or leave empty to keep the current file.
                </p>
                <.live_file_input
                  upload={@uploads.file}
                  class="file-input file-input-bordered w-full"
                />
                <div :if={@uploads.file.entries != []} class="mt-3 space-y-2">
                  <div
                    :for={entry <- @uploads.file.entries}
                    class="flex items-center justify-between rounded-lg border border-base-content/10 px-3 py-2 text-sm"
                  >
                    <div>
                      <p class="font-medium text-base-content">{entry.client_name}</p>
                      <p class="text-xs text-base-content/50">{entry.progress}% uploaded</p>
                    </div>
                    <button
                      type="button"
                      class="text-xs font-semibold uppercase text-base-content/50 hover:text-base-content"
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

            <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <.button type="button" phx-click="close_edit_modal">
                Cancel
              </.button>
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                Save Changes
              </.button>
            </div>
          </form>
        </div>
      </.modal>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp document_stat(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 px-2 py-2 text-center sm:px-3 sm:py-3 sm:text-left">
      <div class="truncate text-[10px] font-semibold uppercase text-base-content/50 sm:text-[11px]">
        {@label}
      </div>
      <div class="mt-0.5 text-lg font-semibold leading-none text-base-content sm:mt-1 sm:text-2xl">
        {@value}
      </div>
    </div>
    """
  end

  attr :document, :any, required: true

  defp document_card(assigns) do
    ~H"""
    <article class="rounded-lg border border-base-content/10 bg-base-100 p-4">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h4 class="text-sm font-semibold text-base-content">{@document.title}</h4>
            <span class="rounded-md bg-primary/10 px-2 py-1 text-xs font-semibold text-primary">
              {document_set_label(@document.kind)}
            </span>
            <span class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70">
              {document_kind_label(@document.kind)}
            </span>
            <span class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70">
              {status_label(@document.status)}
            </span>
          </div>
          <p :if={@document.description} class="mt-2 text-sm leading-5 text-base-content/70">
            {@document.description}
          </p>
          <div :if={document_tags(@document) != []} class="mt-3 flex flex-wrap gap-1.5">
            <span
              :for={tag <- document_tags(@document)}
              class="rounded-md border border-base-content/10 bg-base-200 px-2 py-1 text-xs font-medium text-base-content/65"
            >
              {tag}
            </span>
          </div>
          <dl class="mt-3 grid gap-2 text-sm sm:grid-cols-3">
            <.fact label="Signed" value={date_label(@document.signed_on)} />
            <.fact label="Effective" value={date_label(@document.effective_on)} />
            <.fact label="Expires" value={date_label(@document.expires_on)} />
          </dl>
        </div>
        <div class="flex shrink-0 flex-wrap gap-2">
          <.link
            :if={@document.file_url}
            href={@document.file_url}
            target="_blank"
            class="inline-flex items-center justify-center rounded-md border border-base-content/10 px-3 py-2 text-sm font-semibold text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
          >
            Open File
          </.link>
          <.button phx-click="open_edit_modal" phx-value-id={@document.id}>
            Edit
          </.button>
          <.button
            :if={@document.status != :active}
            phx-click="activate"
            phx-value-id={@document.id}
          >
            Activate
          </.button>
          <.button
            :if={@document.status == :active}
            phx-click="retire"
            phx-value-id={@document.id}
          >
            Retire
          </.button>
        </div>
      </div>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp fact(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-semibold uppercase text-base-content/45">{@label}</dt>
      <dd class="mt-1 text-base-content/75">{@value || "-"}</dd>
    </div>
    """
  end

  defp load_documents(socket) do
    profile = DefaultRegistration.ensure_default().profile

    document_query =
      GnomeGarden.Company.Document
      |> Ash.Query.for_read(:for_company_profile, %{company_profile_id: profile.id})

    {:ok, documents} =
      Company.list_company_documents_for_profile(profile.id, actor: socket.assigns.current_user)

    assign(socket,
      profile: profile,
      documents: documents,
      document_query: document_query
    )
  end

  defp default_form do
    %{"kind" => "other", "status" => "active"}
  end

  defp document_form(document) do
    %{
      "title" => document.title,
      "key" => document.key,
      "kind" => to_string(document.kind || :other),
      "status" => to_string(document.status || :active),
      "description" => document.description,
      "signed_on" => date_value(document.signed_on),
      "effective_on" => date_value(document.effective_on),
      "expires_on" => date_value(document.expires_on),
      "tags" => tags_value(document.metadata)
    }
  end

  defp document_attrs(params, profile_id, upload) do
    title = blank_to_nil(params["title"]) || "Company document"

    %{
      company_profile_id: profile_id,
      key: blank_to_nil(params["key"]) || slug(title),
      title: title,
      kind: atom_param(params["kind"], :other),
      status: atom_param(params["status"], :active),
      description: blank_to_nil(params["description"]),
      signed_on: date_param(params["signed_on"]),
      effective_on: date_param(params["effective_on"]),
      expires_on: date_param(params["expires_on"]),
      metadata: metadata_attrs(%{}, params),
      file: upload
    }
  end

  defp document_update_attrs(params, document) do
    title = blank_to_nil(params["title"]) || "Company document"

    %{
      key: blank_to_nil(params["key"]) || slug(title),
      title: title,
      kind: atom_param(params["kind"], :other),
      status: atom_param(params["status"], :active),
      description: blank_to_nil(params["description"]),
      signed_on: date_param(params["signed_on"]),
      effective_on: date_param(params["effective_on"]),
      expires_on: date_param(params["expires_on"]),
      metadata: metadata_attrs(document.metadata || %{}, params)
    }
  end

  defp metadata_attrs(metadata, params) do
    tags = tags_param(params["tags"])

    if tags == [] do
      Map.delete(metadata, "tags")
    else
      Map.put(metadata, "tags", tags)
    end
  end

  defp tags_param(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp tags_param(_value), do: []

  defp tags_value(metadata) do
    metadata
    |> document_tags()
    |> Enum.join(", ")
  end

  defp document_tags(%{metadata: metadata}), do: document_tags(metadata)
  defp document_tags(%{"tags" => tags}) when is_list(tags), do: Enum.filter(tags, &is_binary/1)
  defp document_tags(_metadata), do: []

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
      [] -> {:error, :no_upload}
    end
  end

  defp consume_optional_upload(socket) do
    case socket.assigns.uploads.file.entries do
      [] -> {:error, :no_upload}
      _entries -> consume_upload(socket)
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

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "company-document-#{System.unique_integer([:positive])}"
      slug -> slug
    end
  end

  defp atom_param(value, _default) when is_binary(value) and value != "",
    do: String.to_existing_atom(value)

  defp atom_param(value, _default) when is_atom(value), do: value
  defp atom_param(_value, default), do: default

  defp date_param(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date_param(_value), do: nil

  defp date_label(%Date{} = date), do: Date.to_iso8601(date)
  defp date_label(_date), do: nil

  defp date_value(%Date{} = date), do: Date.to_iso8601(date)
  defp date_value(_date), do: nil

  defp document_type_count(documents) do
    documents
    |> Enum.map(& &1.kind)
    |> Enum.uniq()
    |> length()
  end

  defp document_set_label(kind) when kind in [:w9, :tax_certificate], do: "Tax identity"
  defp document_set_label(:banking_letter), do: "Bank validation"
  defp document_set_label(:insurance_certificate), do: "Insurance"

  defp document_set_label(kind)
       when kind in [:supplier_code_confirmation, :terms_confirmation],
       do: "Terms and conduct"

  defp document_set_label(:capability_statement), do: "Company profile"
  defp document_set_label(:business_license), do: "Licenses"
  defp document_set_label(_kind), do: "Other"

  defp document_kind_label(kind),
    do: kind |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp status_label(status),
    do: status |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp upload_error_to_string(:too_large), do: "File is too large."
  defp upload_error_to_string(:too_many_files), do: "Only one file can be uploaded."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(error), do: "Upload error: #{inspect(error)}"

  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: Exception.message(error)
end
