defmodule GnomeGardenWeb.Company.ComplianceLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultReviewRecords

  @category_options [
    {"Federal", :federal},
    {"State", :state},
    {"Registered agent", :registered_agent},
    {"Tax", :tax},
    {"License", :license},
    {"Other", :other}
  ]

  @status_options [
    {"Needs review", :needs_review},
    {"Active", :active},
    {"Complete", :complete},
    {"Blocked", :blocked},
    {"Not applicable", :not_applicable}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Company Compliance")
     |> assign(:category_options, @category_options)
     |> assign(:status_options, @status_options)
     |> assign(:form_error, nil)
     |> assign(:form, default_form())
     |> load_obligations()}
  end

  @impl true
  def handle_event("validate", %{"obligation" => params}, socket) do
    {:noreply, assign(socket, :form, Map.merge(default_form(), params))}
  end

  @impl true
  def handle_event("save", %{"obligation" => params}, socket) do
    attrs = obligation_attrs(params, socket.assigns.profile.id)

    case Company.create_company_compliance_obligation(attrs, actor: socket.assigns.current_user) do
      {:ok, _obligation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Compliance item added.")
         |> assign(:form_error, nil)
         |> assign(:form, default_form())
         |> load_obligations()}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:form_error, error_message(error))
         |> assign(:form, params)}
    end
  end

  @impl true
  def handle_event("complete", %{"id" => id}, socket) do
    obligation =
      Company.get_company_compliance_obligation!(id, actor: socket.assigns.current_user)

    {:ok, _obligation} =
      Company.complete_company_compliance_obligation(
        obligation,
        %{completed_on: Date.utc_today()},
        actor: socket.assigns.current_user
      )

    {:noreply, load_obligations(socket)}
  end

  @impl true
  def handle_event("review", %{"id" => id}, socket) do
    obligation =
      Company.get_company_compliance_obligation!(id, actor: socket.assigns.current_user)

    {:ok, _obligation} =
      Company.review_company_compliance_obligation(obligation, actor: socket.assigns.current_user)

    {:noreply, load_obligations(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Company">
        Compliance
        <:subtitle>
          Company-level obligations and renewal checkpoints. Customer-specific requirements stay with onboarding.
        </:subtitle>
      </.page_header>

      <div
        :if={@form_error}
        class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800 dark:border-red-400/20 dark:bg-red-400/10 dark:text-red-100"
      >
        {@form_error}
      </div>

      <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <.section
          title="Obligations"
          description="Track only reusable Gnome obligations here: BOI, SOI, registered agent, franchise tax, and license checks."
        >
          <div class="grid gap-3">
            <.obligation_card :for={obligation <- @obligations} obligation={obligation} />
          </div>
        </.section>

        <.section title="Add Obligation" description="Create a company-level compliance checkpoint.">
          <form id="company-compliance-form" phx-change="validate" phx-submit="save" class="space-y-4">
            <.input name="obligation[title]" label="Title" value={@form["title"]} required />
            <.input name="obligation[key]" label="Key" value={@form["key"]} />
            <.input
              name="obligation[category]"
              label="Category"
              type="select"
              options={@category_options}
              value={@form["category"]}
            />
            <.input
              name="obligation[status]"
              label="Status"
              type="select"
              options={@status_options}
              value={@form["status"]}
            />
            <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-1">
              <.input name="obligation[due_on]" label="Due on" type="date" value={@form["due_on"]} />
              <.input
                name="obligation[completed_on]"
                label="Completed on"
                type="date"
                value={@form["completed_on"]}
              />
            </div>
            <.input name="obligation[source_path]" label="Source path" value={@form["source_path"]} />
            <.input
              name="obligation[summary]"
              label="Summary"
              type="textarea"
              value={@form["summary"]}
            />
            <div class="flex justify-end">
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                Add Obligation
              </.button>
            </div>
          </form>
        </.section>
      </div>
    </.page>
    """
  end

  attr :obligation, :any, required: true

  defp obligation_card(assigns) do
    ~H"""
    <article class="rounded-lg border border-base-content/10 bg-base-100 p-4">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-base font-semibold text-base-content">{@obligation.title}</h3>
            <span class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70">
              {labelize(@obligation.category)}
            </span>
            <span class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70">
              {labelize(@obligation.status)}
            </span>
          </div>
          <p :if={@obligation.summary} class="mt-2 text-sm leading-5 text-base-content/70">
            {@obligation.summary}
          </p>
          <dl class="mt-3 grid gap-2 text-sm sm:grid-cols-3">
            <.fact label="Due" value={date_label(@obligation.due_on)} />
            <.fact label="Completed" value={date_label(@obligation.completed_on)} />
            <.fact label="Source" value={@obligation.source_path} />
          </dl>
        </div>
        <div class="flex shrink-0 flex-wrap gap-2">
          <.button
            :if={@obligation.status != :complete}
            phx-click="complete"
            phx-value-id={@obligation.id}
          >
            Complete
          </.button>
          <.button
            :if={@obligation.status == :complete}
            phx-click="review"
            phx-value-id={@obligation.id}
          >
            Review
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
      <dd class="mt-1 break-words text-base-content/75">{@value || "-"}</dd>
    </div>
    """
  end

  defp load_obligations(socket) do
    defaults = DefaultReviewRecords.ensure_defaults()
    profile = defaults.profile

    {:ok, obligations} =
      Company.list_company_compliance_obligations_for_profile(profile.id,
        actor: socket.assigns.current_user
      )

    assign(socket, profile: profile, obligations: obligations)
  end

  defp default_form, do: %{"category" => "other", "status" => "needs_review"}

  defp obligation_attrs(params, profile_id) do
    title = blank_to_nil(params["title"]) || "Compliance obligation"

    %{
      company_profile_id: profile_id,
      key: blank_to_nil(params["key"]) || slug(title),
      title: title,
      category: atom_param(params["category"], :other),
      status: atom_param(params["status"], :needs_review),
      summary: blank_to_nil(params["summary"]),
      due_on: date_param(params["due_on"]),
      completed_on: date_param(params["completed_on"]),
      source_path: blank_to_nil(params["source_path"])
    }
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "compliance-#{System.unique_integer([:positive])}"
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

  defp labelize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: Exception.message(error)
end
