defmodule GnomeGardenWeb.Documents.DocumentsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Documents
  alias GnomeGarden.Documents.DocumentSendWorker
  alias GnomeGarden.Operations
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.DocumentEmail

  @impl true
  def mount(_params, _session, socket) do
    {:ok, docs} = Documents.list_active_documents()

    {:ok,
     socket
     |> assign(:page_title, "Company Documents")
     |> assign(:docs, docs)
     |> assign(:all_docs, docs)
     |> assign(:show_all_versions, false)
     |> assign(:search, "")
     |> assign(:category_filter, "all")
     |> assign(:send_modal_open, false)
     |> assign(:send_doc, nil)
     |> assign(:send_to, "")
     |> assign(:send_subject, "")
     |> assign(:send_message, "")
     |> assign(:send_org_id, nil)
     |> assign(:send_ok, false)
     |> assign(:send_error, nil)
     |> assign(:history_modal_open, false)
     |> assign(:history_doc, nil)
     |> assign(:history_versions, [])
     |> assign(:bulk_modal_open, false)
     |> assign(:selected_doc_ids, [])
     |> assign(:bulk_orgs, [])
     |> assign(:bulk_selected_org_ids, [])
     |> assign(:bulk_message, "")
     |> assign(:bulk_ok, false)
     |> assign(:bulk_error, nil)
     |> assign(:show_send_log, false)
     |> assign(:send_logs, [])
     |> assign(:send_log_org_names, %{})
     |> assign(:upload_modal_open, false)
     |> assign(:upload_error, nil)
     |> allow_upload(:file,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 25_000_000
     )}
  end

  @impl true
  def handle_event("search", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:search, value) |> apply_filters()}
  end

  @impl true
  def handle_event("filter_category", %{"category" => cat}, socket) do
    {:noreply, socket |> assign(:category_filter, cat) |> apply_filters()}
  end

  @impl true
  def handle_event("toggle_all_versions", _params, socket) do
    show_all = !socket.assigns.show_all_versions

    docs =
      if show_all do
        {:ok, all} = Documents.list_all_documents()
        all
      else
        {:ok, active} = Documents.list_active_documents()
        active
      end

    {:noreply,
     socket
     |> assign(:show_all_versions, show_all)
     |> assign(:all_docs, docs)
     |> assign(:docs, docs)
     |> apply_filters()}
  end

  @impl true
  def handle_event("toggle_doc_select", %{"doc-id" => doc_id}, socket) do
    selected = socket.assigns.selected_doc_ids

    updated =
      if doc_id in selected do
        List.delete(selected, doc_id)
      else
        [doc_id | selected]
      end

    {:noreply, assign(socket, :selected_doc_ids, updated)}
  end

  @impl true
  def handle_event("open_send_modal", %{"doc-id" => doc_id}, socket) do
    doc = Enum.find(socket.assigns.all_docs, &(to_string(&1.id) == doc_id))

    {:noreply,
     socket
     |> assign(:send_modal_open, true)
     |> assign(:send_doc, doc)
     |> assign(:send_to, "")
     |> assign(:send_subject, "Gnome Automation — #{doc.name}")
     |> assign(:send_message, "")
     |> assign(:send_ok, false)
     |> assign(:send_error, nil)}
  end

  @impl true
  def handle_event("close_send_modal", _params, socket) do
    {:noreply, assign(socket, :send_modal_open, false)}
  end

  @impl true
  def handle_event("send_document", %{"send_doc" => params}, socket) do
    to = Map.get(params, "to", "") |> String.trim()
    message = Map.get(params, "message", "") |> String.trim()
    doc = socket.assigns.send_doc
    user = socket.assigns.current_user

    if to == "" do
      {:noreply, assign(socket, :send_error, "Email address is required")}
    else
      email = DocumentEmail.build(doc, to, message: if(message == "", do: nil, else: message))

      case Mailer.deliver(email) do
        {:ok, _} ->
          {:ok, _} = Documents.log_send(%{
            company_document_id: doc.id,
            organization_id: socket.assigns.send_org_id,
            sent_to_email: to,
            sent_by_user_id: user.id,
            message: if(message == "", do: nil, else: message)
          })

          {:noreply,
           socket
           |> assign(:send_modal_open, false)
           |> assign(:send_ok, true)
           |> put_flash(:info, "Document sent to #{to}")}

        {:error, reason} ->
          {:noreply, assign(socket, :send_error, "Failed to send: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("open_history_modal", %{"doc-id" => doc_id}, socket) do
    {:ok, all} = Documents.list_all_documents()
    doc = Enum.find(all, &(to_string(&1.id) == doc_id))
    versions = build_version_chain(doc, all)

    {:noreply,
     socket
     |> assign(:history_modal_open, true)
     |> assign(:history_doc, doc)
     |> assign(:history_versions, versions)}
  end

  @impl true
  def handle_event("close_history_modal", _params, socket) do
    {:noreply, assign(socket, :history_modal_open, false)}
  end

  @impl true
  def handle_event("open_bulk_modal", _params, socket) do
    orgs = Operations.list_organizations!(actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:bulk_modal_open, true)
     |> assign(:bulk_orgs, orgs)
     |> assign(:bulk_selected_org_ids, [])
     |> assign(:bulk_message, "")
     |> assign(:bulk_ok, false)
     |> assign(:bulk_error, nil)}
  end

  @impl true
  def handle_event("close_bulk_modal", _params, socket) do
    {:noreply, assign(socket, :bulk_modal_open, false)}
  end

  @impl true
  def handle_event("toggle_bulk_org", %{"org-id" => org_id}, socket) do
    selected = socket.assigns.bulk_selected_org_ids

    updated =
      if org_id in selected do
        List.delete(selected, org_id)
      else
        [org_id | selected]
      end

    {:noreply, assign(socket, :bulk_selected_org_ids, updated)}
  end

  @impl true
  def handle_event("bulk_send", %{"bulk" => params}, socket) do
    org_ids = socket.assigns.bulk_selected_org_ids
    doc_ids = socket.assigns.selected_doc_ids
    message = Map.get(params, "message", "") |> String.trim()
    user = socket.assigns.current_user

    cond do
      Enum.empty?(org_ids) ->
        {:noreply, assign(socket, :bulk_error, "Select at least one organization")}
      Enum.empty?(doc_ids) ->
        {:noreply, assign(socket, :bulk_error, "No documents selected")}
      true ->
        jobs =
          for doc_id <- doc_ids, org_id <- org_ids do
            DocumentSendWorker.new(%{
              document_id: doc_id,
              organization_id: org_id,
              sent_by_user_id: user.id,
              message: if(message == "", do: nil, else: message)
            })
          end

        Oban.insert_all(jobs)

        total = length(jobs)
        {:noreply,
         socket
         |> assign(:bulk_modal_open, false)
         |> assign(:selected_doc_ids, [])
         |> put_flash(:info, "Sending to #{total} recipient(s) in the background")}
    end
  end

  @impl true
  def handle_event("toggle_send_log", _params, socket) do
    show = !socket.assigns.show_send_log

    {logs, org_names} =
      if show do
        {:ok, raw_logs} = Documents.list_send_logs()
        logs = Ash.load!(raw_logs, [:company_document], authorize?: false)

        org_ids = logs |> Enum.map(& &1.organization_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        org_names =
          if Enum.empty?(org_ids) do
            %{}
          else
            Operations.list_organizations!(actor: socket.assigns.current_user)
            |> Enum.filter(&(&1.id in org_ids))
            |> Map.new(&{&1.id, &1.name})
          end

        {logs, org_names}
      else
        {[], %{}}
      end

    {:noreply,
     socket
     |> assign(:show_send_log, show)
     |> assign(:send_logs, logs)
     |> assign(:send_log_org_names, org_names)}
  end

  @impl true
  def handle_event("open_upload_modal", _params, socket) do
    {:noreply, assign(socket, upload_modal_open: true, upload_error: nil)}
  end

  @impl true
  def handle_event("close_upload_modal", _params, socket) do
    {:noreply, assign(socket, :upload_modal_open, false)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_document", %{"doc" => params}, socket) do
    entries = socket.assigns.uploads.file.entries

    if Enum.empty?(entries) do
      {:noreply, assign(socket, :upload_error, "Please select a PDF file to upload")}
    else
      result =
        consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
          preserved_path =
            Path.join(
              System.tmp_dir!(),
              "#{Ecto.UUID.generate()}-#{entry.client_name |> String.replace(~r/[^a-zA-Z0-9._-]/u, "-") |> String.trim("-")}"
            )

          File.cp!(path, preserved_path)

          file = %Plug.Upload{
            path: preserved_path,
            filename: entry.client_name,
            content_type: entry.client_type
          }

          result =
            Documents.create_document(%{
              name: params["name"],
              category: String.to_existing_atom(params["category"]),
              version: params["version"],
              description: if(params["description"] != "", do: params["description"]),
              status: :active,
              file: file
            })

          File.rm(preserved_path)
          result
        end)

      case List.first(result) do
        {:ok, _doc} ->
          {:ok, docs} = Documents.list_active_documents()

          {:noreply,
           socket
           |> assign(:upload_modal_open, false)
           |> assign(:all_docs, docs)
           |> apply_filters()
           |> put_flash(:info, "Document uploaded successfully")}

        {:error, reason} ->
          {:noreply, assign(socket, :upload_error, "Upload failed: #{inspect(reason)}")}

        nil ->
          {:noreply, assign(socket, :upload_error, "No file was processed")}
      end
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Company Documents
        <:subtitle>Internal documents sent to clients — W9, legal forms, compliance files.</:subtitle>
        <:actions>
          <button
            type="button"
            phx-click="open_upload_modal"
            class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
          >
            <.icon name="hero-arrow-up-tray" class="size-4 mr-1 inline" /> Upload Document
          </button>
          <.button
            :if={length(@selected_doc_ids) > 0}
            phx-click="open_bulk_modal"
            variant="primary"
          >
            Batch Send ({length(@selected_doc_ids)})
          </.button>
        </:actions>
      </.page_header>

      <%!-- Controls --%>
      <div class="mb-4 flex flex-wrap items-center gap-3">
        <input
          type="text"
          placeholder="Search documents..."
          phx-keyup="search"
          phx-debounce="200"
          name="search"
          value={@search}
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
        />

        <form phx-change="filter_category">
          <select
            name="category"
            class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 appearance-none"
          >
            <option value="all">All Categories</option>
            <option value="tax" selected={@category_filter == "tax"}>Tax</option>
            <option value="legal" selected={@category_filter == "legal"}>Legal</option>
            <option value="compliance" selected={@category_filter == "compliance"}>Compliance</option>
            <option value="hr" selected={@category_filter == "hr"}>HR</option>
            <option value="other" selected={@category_filter == "other"}>Other</option>
          </select>
        </form>

        <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300 cursor-pointer">
          <input
            type="checkbox"
            phx-click="toggle_all_versions"
            checked={@show_all_versions}
            class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
          />
          Show all versions
        </label>
      </div>

      <%!-- Documents Table --%>
      <div class="rounded-lg border border-gray-200 bg-white dark:border-white/10 dark:bg-white/5 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="w-8 px-4 py-3"></th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Name</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Category</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Version</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Status</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Expires</th>
              <th class="px-4 py-3 text-right font-medium text-gray-500 dark:text-gray-400">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 dark:divide-white/5">
            <tr :for={doc <- @docs} class="hover:bg-gray-50 dark:hover:bg-white/5">
              <td class="px-4 py-3">
                <input
                  type="checkbox"
                  phx-click="toggle_doc_select"
                  phx-value-doc-id={doc.id}
                  checked={doc.id in @selected_doc_ids}
                  class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
                />
              </td>
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-white">{doc.name}</td>
              <td class="px-4 py-3">
                <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{category_badge_class(doc.category)}"}>
                  {String.capitalize(to_string(doc.category))}
                </span>
              </td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-400">{doc.version}</td>
              <td class="px-4 py-3">
                <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{status_badge_class(doc.status)}"}>
                  {String.capitalize(to_string(doc.status))}
                </span>
              </td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                {doc.expiry_date || "—"}
              </td>
              <td class="px-4 py-3 text-right">
                <div class="flex items-center justify-end gap-2">
                  <a
                    href={"/" <> doc.file_path}
                    download
                    target="_blank"
                    class="rounded-md border border-gray-300 px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50 dark:border-white/20 dark:text-gray-300 dark:hover:bg-white/10 cursor-pointer transition-colors"
                  >
                    Download
                  </a>
                  <button
                    type="button"
                    phx-click="open_send_modal"
                    phx-value-doc-id={doc.id}
                    class="rounded-md border border-emerald-600 px-2.5 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-50 dark:border-emerald-500 dark:text-emerald-400 dark:hover:bg-emerald-900/30 cursor-pointer transition-colors"
                  >
                    Send
                  </button>
                  <button
                    type="button"
                    phx-click="open_history_modal"
                    phx-value-doc-id={doc.id}
                    class="rounded-md border border-gray-300 px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50 dark:border-white/20 dark:text-gray-300 dark:hover:bg-white/10 cursor-pointer transition-colors"
                  >
                    History
                  </button>
                </div>
              </td>
            </tr>
            <tr :if={Enum.empty?(@docs)}>
              <td colspan="7" class="px-4 py-8 text-center text-sm text-gray-500 dark:text-gray-400">
                No documents found.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Send Log Toggle --%>
      <div class="mt-6">
        <button
          type="button"
          phx-click="toggle_send_log"
          class="inline-flex items-center gap-x-1.5 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-white/10 dark:text-white dark:ring-white/20 dark:hover:bg-white/20"
        >
          <.icon
            name={if @show_send_log, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
            class="-ml-0.5 size-4 text-gray-400 dark:text-gray-300"
          />
          {if @show_send_log, do: "Hide Send Log", else: "Show Send Log"}
        </button>

        <div :if={@show_send_log} class="mt-4 rounded-lg border border-gray-200 bg-white dark:border-white/10 dark:bg-white/5 overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
            <thead class="bg-gray-50 dark:bg-white/5">
              <tr>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Date Sent</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Document</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Version</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Org</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Sent To</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 dark:divide-white/5">
              <tr :for={log <- @send_logs} class="hover:bg-gray-50 dark:hover:bg-white/5">
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                  {Calendar.strftime(log.sent_at, "%b %d, %Y %H:%M")}
                </td>
                <td class="px-4 py-3 text-gray-900 dark:text-white">
                  {log.company_document && log.company_document.name}
                </td>
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                  {log.company_document && log.company_document.version}
                </td>
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                  {Map.get(@send_log_org_names, log.organization_id, "—")}
                </td>
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">{log.sent_to_email}</td>
              </tr>
              <tr :if={Enum.empty?(@send_logs)}>
                <td colspan="5" class="px-4 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
                  No sends recorded yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Send Modal --%>
      <div
        :if={@send_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      >
        <div class="w-full max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
          <h2 class="mb-4 text-base font-semibold text-gray-900 dark:text-white">
            Send Document
          </h2>

          <div :if={@send_doc} class="mb-4 rounded-md bg-gray-50 px-3 py-2 text-sm text-gray-700 dark:bg-white/5 dark:text-gray-300">
            <strong>{@send_doc.name}</strong> — v{@send_doc.version}
          </div>

          <form id="send-document-form" phx-submit="send_document">
            <div class="space-y-4">
              <div>
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
                <input
                  type="email"
                  name="send_doc[to]"
                  value={@send_to}
                  required
                  placeholder="client@example.com"
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div>
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Subject</label>
                <input
                  type="text"
                  name="send_doc[subject]"
                  value={@send_subject}
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div>
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Message (optional)</label>
                <textarea
                  name="send_doc[message]"
                  rows="3"
                  placeholder="Please keep this on file for your records."
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
                ></textarea>
              </div>
            </div>

            <div :if={@send_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {@send_error}
            </div>

            <div class="mt-5 flex justify-end gap-3">
              <button type="button" phx-click="close_send_modal" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Send
              </button>
            </div>
          </form>
        </div>
      </div>

      <%!-- Version History Modal --%>
      <div
        :if={@history_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      >
        <div class="w-full max-w-lg rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              Version History — {@history_doc && @history_doc.name}
            </h2>
            <button type="button" phx-click="close_history_modal" class="text-gray-400 hover:text-gray-600">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <table class="min-w-full text-sm">
            <thead>
              <tr class="border-b border-gray-200 dark:border-white/10">
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Version</th>
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Status</th>
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Added</th>
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Expires</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={v <- @history_versions} class="border-b border-gray-100 dark:border-white/5">
                <td class="py-2 font-medium text-gray-900 dark:text-white">{v.version}</td>
                <td class="py-2">
                  <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{status_badge_class(v.status)}"}>
                    {String.capitalize(to_string(v.status))}
                  </span>
                </td>
                <td class="py-2 text-gray-600 dark:text-gray-400">
                  {Calendar.strftime(v.inserted_at, "%b %d, %Y")}
                </td>
                <td class="py-2 text-gray-600 dark:text-gray-400">{v.expiry_date || "—"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Bulk Send Modal --%>
      <div
        :if={@bulk_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      >
        <div class="w-full max-w-lg rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              Batch Send ({length(@selected_doc_ids)} document(s))
            </h2>
            <button type="button" phx-click="close_bulk_modal" class="text-gray-400 hover:text-gray-600">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <p class="mb-3 text-sm text-gray-600 dark:text-gray-400">
            Select the organizations to send to. Each org will receive all selected documents.
          </p>

          <form id="bulk-send-form" phx-submit="bulk_send">
            <div class="mb-4 max-h-48 overflow-y-auto rounded-md border border-gray-200 dark:border-white/10 p-2 space-y-1">
              <label :for={org <- @bulk_orgs} class="flex items-center gap-2 rounded px-2 py-1 hover:bg-gray-50 dark:hover:bg-white/5 cursor-pointer text-sm text-gray-900 dark:text-white">
                <input
                  type="checkbox"
                  phx-click="toggle_bulk_org"
                  phx-value-org-id={org.id}
                  checked={org.id in @bulk_selected_org_ids}
                  class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
                />
                {org.name}
              </label>
            </div>

            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Message (optional)</label>
              <textarea
                name="bulk[message]"
                rows="2"
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
              ></textarea>
            </div>

            <div :if={@bulk_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {@bulk_error}
            </div>

            <div class="mt-5 flex justify-end gap-3">
              <button type="button" phx-click="close_bulk_modal" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Send to {length(@bulk_selected_org_ids)} org(s)
              </button>
            </div>
          </form>
        </div>
      </div>
      <%!-- Upload Document Modal --%>
      <div
        :if={@upload_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      >
        <div class="w-full max-w-lg rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">Upload Document</h2>
            <button type="button" phx-click="close_upload_modal" class="text-gray-400 hover:text-gray-600">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <form
            id="upload-document-form"
            phx-submit="save_document"
            phx-change="validate_upload"
          >
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
              <div class="sm:col-span-4">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Name</label>
                <input
                  type="text"
                  name="doc[name]"
                  required
                  placeholder="e.g. W9 Form"
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div class="sm:col-span-2">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Version</label>
                <input
                  type="text"
                  name="doc[version]"
                  required
                  placeholder="e.g. 2024"
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div class="sm:col-span-3">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Category</label>
                <select
                  name="doc[category]"
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 appearance-none"
                >
                  <option value="tax">Tax</option>
                  <option value="legal">Legal</option>
                  <option value="compliance">Compliance</option>
                  <option value="hr">HR</option>
                  <option value="other">Other</option>
                </select>
              </div>

              <div class="sm:col-span-6">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Description (optional)</label>
                <input
                  type="text"
                  name="doc[description]"
                  placeholder="Short description"
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div class="sm:col-span-6">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">PDF File</label>
                <.live_file_input upload={@uploads.file} class="mt-1 block w-full text-sm text-gray-600 dark:text-gray-300" />
                <p :for={entry <- @uploads.file.entries} class="mt-1 text-xs text-gray-500">
                  {entry.client_name} ({Float.round(entry.client_size / 1_000_000, 1)} MB)
                </p>
                <p :for={err <- upload_errors(@uploads.file)} class="mt-1 text-xs text-red-600">
                  {err}
                </p>
              </div>
            </div>

            <div :if={@upload_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {@upload_error}
            </div>

            <div class="mt-6 flex justify-end gap-3">
              <button type="button" phx-click="close_upload_modal" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Upload
              </button>
            </div>
          </form>
        </div>
      </div>
    </.page>
    """
  end

  # --- Private helpers ---

  defp apply_filters(socket) do
    search = String.downcase(socket.assigns.search)
    cat = socket.assigns.category_filter

    filtered =
      socket.assigns.all_docs
      |> Enum.filter(fn doc ->
        name_match = search == "" or String.contains?(String.downcase(doc.name), search)
        cat_match = cat == "all" or to_string(doc.category) == cat
        name_match and cat_match
      end)

    assign(socket, :docs, filtered)
  end

  defp build_version_chain(doc, all_docs) do
    Enum.filter(all_docs, &(&1.name == doc.name))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp category_badge_class(:tax), do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
  defp category_badge_class(:legal), do: "bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400"
  defp category_badge_class(:compliance), do: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400"
  defp category_badge_class(:hr), do: "bg-pink-100 text-pink-700 dark:bg-pink-900/30 dark:text-pink-400"
  defp category_badge_class(_), do: "bg-gray-100 text-gray-600 dark:bg-white/10 dark:text-gray-400"

  defp status_badge_class(:active), do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"
  defp status_badge_class(:superseded), do: "bg-gray-100 text-gray-500 dark:bg-white/10 dark:text-gray-400"
  defp status_badge_class(:expired), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-500 dark:bg-white/10 dark:text-gray-400"
end
