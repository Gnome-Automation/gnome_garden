defmodule GnomeGardenWeb.Finance.BankTransactionLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Banking

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Bank Transaction")
     |> assign(:category_options, bank_transaction_category_options())
     |> load_workspace(id)}
  end

  @impl true
  def handle_event("validate_category", %{"category" => params}, socket) do
    {:noreply, assign(socket, :category_form, Map.merge(category_form(socket), params))}
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    transaction = socket.assigns.transaction

    attrs = %{
      category: atom_param(params["category"]),
      reconciliation_note: blank_to_nil(params["reconciliation_note"])
    }

    case Banking.categorize_bank_transaction(transaction, attrs,
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction categorized.")
         |> load_workspace(updated.id)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("review", _params, socket) do
    transaction = socket.assigns.transaction

    case Banking.mark_bank_transaction_reviewed(
           transaction,
           %{reconciliation_note: review_note(socket, "Reviewed from transaction detail")},
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction marked reviewed.")
         |> load_workspace(updated.id)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("ignore", _params, socket) do
    transaction = socket.assigns.transaction

    case Banking.ignore_bank_transaction(
           transaction,
           %{reconciliation_note: review_note(socket, "Ignored from transaction detail")},
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction ignored.")
         |> load_workspace(updated.id)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("reopen", _params, socket) do
    transaction = socket.assigns.transaction

    case Banking.reopen_bank_transaction_review(transaction, %{},
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transaction reopened.")
         |> load_workspace(updated.id)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("accept_match", %{"id" => id}, socket) do
    with {:ok, match} <-
           Banking.get_bank_transaction_match(id, actor: socket.assigns.current_user),
         {:ok, _match} <-
           Banking.accept_bank_transaction_match(
             match,
             %{note: "Accepted from transaction detail"},
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Match accepted.")
       |> load_workspace(socket.assigns.transaction.id)}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("reject_match", %{"id" => id}, socket) do
    with {:ok, match} <-
           Banking.get_bank_transaction_match(id, actor: socket.assigns.current_user),
         {:ok, _match} <-
           Banking.reject_bank_transaction_match(
             match,
             %{note: "Rejected from transaction detail"},
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Match rejected.")
       |> load_workspace(socket.assigns.transaction.id)}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("create_rule", _params, socket) do
    transaction = socket.assigns.transaction

    case Banking.create_bank_rule_from_transaction(transaction.id,
           actor: socket.assigns.current_user
         ) do
      {:ok, %{rule: rule}} ->
        {:noreply,
         socket
         |> assign(:created_rule, rule)
         |> put_flash(:info, "Bank rule created from transaction.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <%= if @transaction_missing? do %>
        <.page_header eyebrow="Finance">
          Bank transaction not found
          <:subtitle>
            This transaction may have been deleted, or the link may point to an unknown transaction.
          </:subtitle>
          <:actions>
            <.button navigate={~p"/finance/banking/review"}>
              <.icon name="hero-queue-list" class="size-4" /> Review Queue
            </.button>
            <.button navigate={~p"/finance/banking"}>
              <.icon name="hero-building-library" class="size-4" /> Banking
            </.button>
          </:actions>
        </.page_header>

        <.section
          title="Transaction unavailable"
          description="Return to the review queue or banking workspace to choose an available transaction."
        >
          <.empty_state
            icon="hero-exclamation-triangle"
            title="No transaction details to show"
            description="The requested bank transaction could not be loaded."
            class="py-10"
          />
        </.section>
      <% else %>
        <.page_header eyebrow="Finance">
          {bank_transaction_counterparty(@transaction)}
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-2">
              <.status_badge status={bank_review_status_variant(@transaction.review_status)}>
                {format_atom(@transaction.review_status)}
              </.status_badge>
              <.status_badge status={bank_match_status_variant(@transaction.match_status)}>
                {bank_match_status_label(@transaction.match_status)}
              </.status_badge>
              <span class="text-base-content/40">/</span>
              <span>{format_amount(@transaction.amount)}</span>
            </span>
          </:subtitle>
          <:actions>
            <.button navigate={back_to_account_path(@bank_account)}>
              <.icon name="hero-building-library" class="size-4" /> Account
            </.button>
            <.button navigate={~p"/finance/banking/review"}>
              <.icon name="hero-queue-list" class="size-4" /> Review Queue
            </.button>
            <.button navigate={~p"/finance/banking"}>
              <.icon name="hero-arrow-left" class="size-4" /> Banking
            </.button>
          </:actions>
        </.page_header>

        <div class="grid grid-cols-2 gap-2 sm:gap-3 xl:grid-cols-4">
          <.stat_card
            title="Amount"
            value={format_amount(@transaction.amount)}
            description={format_atom(@transaction.direction)}
            icon="hero-banknotes"
          />
          <.stat_card
            title="Category"
            value={format_atom(@transaction.category)}
            description="Current finance category."
            icon="hero-tag"
            accent="sky"
          />
          <.stat_card
            title="Matches"
            value={Integer.to_string(@workspace.match_count)}
            description={"#{@workspace.pending_match_count} suggested."}
            icon="hero-link"
            accent="amber"
          />
          <.stat_card
            title="Events"
            value={Integer.to_string(@workspace.event_count)}
            description="Audit trail entries."
            icon="hero-clock"
            accent="rose"
          />
        </div>

        <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
          <div class="space-y-4">
            <.section
              title="Transaction"
              description="Provider-neutral transaction details mirrored into Finance."
            >
              <div class="grid gap-5 sm:grid-cols-2">
                <.property_item label="Account" value={account_name(@bank_account)} />
                <.property_item label="Provider ID" value={@transaction.provider_transaction_id} />
                <.property_item label="Occurred" value={format_datetime(@transaction.occurred_at)} />
                <.property_item label="Posted" value={format_datetime(@transaction.posted_at)} />
                <.property_item label="Kind" value={format_atom(@transaction.kind)} />
                <.property_item label="Status" value={format_atom(@transaction.status)} />
                <.property_item label="Counterparty ID" value={@transaction.counterparty_id || "-"} />
                <.property_item
                  label="Counterparty Last 4"
                  value={masked_last4(@transaction.counterparty_account_last4)}
                />
              </div>

              <div class="mt-5 grid gap-4">
                <div>
                  <p class="text-xs font-semibold uppercase text-base-content/50">Description</p>
                  <p class="mt-1 text-sm text-base-content/75">
                    {@transaction.description || "-"}
                  </p>
                </div>
                <div>
                  <p class="text-xs font-semibold uppercase text-base-content/50">Memo</p>
                  <p class="mt-1 whitespace-pre-wrap text-sm text-base-content/75">
                    {@transaction.memo || "-"}
                  </p>
                </div>
                <div>
                  <p class="text-xs font-semibold uppercase text-base-content/50">Review Notes</p>
                  <p class="mt-1 whitespace-pre-wrap text-sm text-base-content/75">
                    {@transaction.reconciliation_note || "-"}
                  </p>
                </div>
              </div>
            </.section>

            <.section
              title="Match Candidates"
              description="Suggested or accepted links between this bank transaction and receivable state."
            >
              <div :if={@matches == []}>
                <.empty_state
                  icon="hero-link"
                  title="No match candidates"
                  description="Potential payment and invoice matches will appear here."
                />
              </div>

              <div :if={@matches != []} class="space-y-3">
                <.match_card :for={match <- @matches} match={match} />
              </div>
            </.section>

            <.section title="Event Timeline" description="Finance audit events for this transaction.">
              <div :if={@events == []}>
                <.empty_state
                  icon="hero-clock"
                  title="No events yet"
                  description="Review, categorization, match, and sync events will appear here."
                />
              </div>

              <div :if={@events != []} class="space-y-3">
                <.event_card :for={event <- @events} event={event} />
              </div>
            </.section>
          </div>

          <aside class="space-y-4">
            <.section
              title="Review Actions"
              description="Use the same Finance transaction workflow actions as the banking queue."
            >
              <form
                id="bank-transaction-category-form"
                phx-change="validate_category"
                phx-submit="save_category"
                class="space-y-4"
              >
                <.input
                  type="select"
                  name="category[category]"
                  value={@category_form["category"]}
                  label="Category"
                  options={@category_options}
                />
                <.input
                  type="textarea"
                  name="category[reconciliation_note]"
                  value={@category_form["reconciliation_note"]}
                  label="Review note"
                  placeholder="Why this decision is correct"
                />

                <.button type="submit" variant="primary" class="w-full">
                  <.icon name="hero-tag" class="size-4" /> Save Category
                </.button>
              </form>

              <div class="mt-4 grid gap-2">
                <.button phx-click="review" class="w-full">
                  <.icon name="hero-check" class="size-4" /> Mark Reviewed
                </.button>
                <.button phx-click="ignore" class="w-full">
                  <.icon name="hero-no-symbol" class="size-4" /> Ignore
                </.button>
                <.button phx-click="reopen" class="w-full">
                  <.icon name="hero-arrow-uturn-left" class="size-4" /> Reopen Review
                </.button>
              </div>
            </.section>

            <.section title="Provider" description="Source hints for reconciliation.">
              <div class="grid gap-3 text-sm">
                <.property_item label="Provider" value={format_atom(@transaction.provider)} />
                <.property_item label="Dashboard" value={@transaction.dashboard_link || "-"} />
              </div>
            </.section>

            <.section
              title="Rule Suggestion"
              description="Create repeatable automation from this reviewed transaction."
            >
              <div :if={rule_creatable?(@transaction)} class="space-y-3">
                <div class="rounded-lg border border-base-content/10 bg-base-200 p-3 text-sm">
                  <p class="font-semibold text-base-content">
                    {rule_name_from_transaction(@transaction)}
                  </p>
                  <dl class="mt-3 grid gap-2 text-xs">
                    <div class="flex items-start justify-between gap-3">
                      <dt class="text-base-content/45">Direction</dt>
                      <dd class="font-medium">{format_atom(@transaction.direction)}</dd>
                    </div>
                    <div class="flex items-start justify-between gap-3">
                      <dt class="text-base-content/45">Category</dt>
                      <dd class="font-medium">{format_atom(@transaction.category)}</dd>
                    </div>
                    <div class="flex items-start justify-between gap-3">
                      <dt class="text-base-content/45">Counterparty</dt>
                      <dd class="text-right font-medium">
                        {bank_transaction_counterparty(@transaction)}
                      </dd>
                    </div>
                  </dl>
                </div>

                <.button
                  :if={is_nil(@created_rule)}
                  phx-click="create_rule"
                  variant="primary"
                  class="w-full"
                >
                  <.icon name="hero-funnel" class="size-4" /> Create Rule
                </.button>

                <p :if={@created_rule} class="text-sm text-success">
                  Rule created: {@created_rule.name}
                </p>

                <.button
                  :if={@created_rule}
                  navigate={~p"/finance/banking/rules"}
                  class="w-full"
                >
                  <.icon name="hero-arrow-right" class="size-4" /> Open Rules
                </.button>
              </div>

              <.empty_state
                :if={!rule_creatable?(@transaction)}
                icon="hero-funnel"
                title="Review before creating a rule"
                description="Categorize and review this transaction before turning it into automation."
                class="py-6"
              />
            </.section>
          </aside>
        </div>
      <% end %>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp property_item(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/40">
        {@label}
      </p>
      <p class="break-words text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  attr :match, :map, required: true

  defp match_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="text-sm font-semibold text-base-content">
            {journal_entry_label(@match.journal_entry)}
          </p>
          <p class="mt-1 text-xs text-base-content/55">
            {format_amount(@match.amount)}
          </p>
        </div>
        <.status_badge status={match_status_variant(@match.status)}>
          {format_atom(@match.status)}
        </.status_badge>
      </div>

      <div :if={@match.confidence} class="mt-3 flex flex-wrap gap-1.5">
        <.status_badge status={:info}>{format_confidence(@match.confidence)}</.status_badge>
      </div>

      <p :if={@match.note} class="mt-3 text-xs text-base-content/60">
        {@match.note}
      </p>

      <div :if={@match.status == :proposed} class="mt-3 flex flex-wrap gap-2">
        <.button phx-click="accept_match" phx-value-id={@match.id} variant="primary">
          <.icon name="hero-check" class="size-4" /> Accept
        </.button>
        <.button phx-click="reject_match" phx-value-id={@match.id}>
          <.icon name="hero-x-mark" class="size-4" /> Reject
        </.button>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  defp event_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 p-3">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="text-sm font-semibold text-base-content">
            {format_atom(@event.event_type)}
          </p>
          <p class="mt-1 text-xs text-base-content/55">
            {format_atom(@event.source)} · {format_datetime(@event.inserted_at)}
          </p>
        </div>
        <span class={["shrink-0 text-xs", bank_amount_classes(@event.amount)]}>
          {format_amount(@event.amount)}
        </span>
      </div>

      <p :if={@event.message} class="mt-3 text-xs text-base-content/60">
        {@event.message}
      </p>

      <dl :if={map_size(@event.metadata || %{}) > 0} class="mt-3 grid gap-2 text-xs">
        <div :for={{key, value} <- @event.metadata} class="flex items-start justify-between gap-3">
          <dt class="text-base-content/45">{format_metadata_key(key)}</dt>
          <dd class="text-right font-medium text-base-content/70">{to_string(value)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp load_workspace(socket, id) do
    case Banking.get_bank_transaction_workspace(id, actor: socket.assigns.current_user) do
      {:ok, workspace} ->
        transaction = workspace.transaction

        socket
        |> assign(:page_title, bank_transaction_counterparty(transaction))
        |> assign(:transaction_missing?, false)
        |> assign(:workspace, workspace)
        |> assign(:transaction, transaction)
        |> assign(:bank_account, workspace.bank_account)
        |> assign(:matches, workspace.matches)
        |> assign(:events, Enum.reverse(workspace.events))
        |> assign(:created_rule, nil)
        |> assign(:category_form, %{
          "category" => Atom.to_string(transaction.category || :unknown),
          "reconciliation_note" => transaction.reconciliation_note || ""
        })

      {:error, error} ->
        if missing_transaction_error?(error) do
          socket
          |> assign(:page_title, "Bank transaction not found")
          |> assign(:transaction_missing?, true)
          |> assign(:requested_transaction_id, id)
          |> assign(:workspace, nil)
          |> assign(:transaction, nil)
          |> assign(:bank_account, nil)
          |> assign(:matches, [])
          |> assign(:events, [])
          |> assign(:created_rule, nil)
          |> assign(:category_form, %{})
        else
          raise error
        end
    end
  end

  defp missing_transaction_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &missing_transaction_error?/1)
  end

  defp missing_transaction_error?(%Ash.Error.Query.NotFound{}), do: true
  defp missing_transaction_error?(_error), do: false

  defp category_form(socket), do: socket.assigns.category_form || %{}

  defp review_note(socket, fallback) do
    socket.assigns.category_form
    |> Map.get("reconciliation_note")
    |> blank_to_nil()
    |> Kernel.||(fallback)
  end

  defp account_name(%Ash.NotLoaded{}), do: "-"
  defp account_name(nil), do: "-"
  defp account_name(%{name: name}), do: name

  defp back_to_account_path(%Ash.NotLoaded{}), do: ~p"/finance/banking"
  defp back_to_account_path(nil), do: ~p"/finance/banking"
  defp back_to_account_path(%{id: id}), do: ~p"/finance/banking/accounts/#{id}"

  defp masked_last4(nil), do: "-"
  defp masked_last4(value), do: "****#{value}"

  defp journal_entry_label(%Ash.NotLoaded{}), do: "Ledger entry"
  defp journal_entry_label(nil), do: "Ledger entry"

  defp journal_entry_label(%{entry_number: number, description: description})
       when is_binary(number) and is_binary(description),
       do: "#{number} · #{description}"

  defp journal_entry_label(%{entry_number: number}) when is_binary(number), do: number
  defp journal_entry_label(%{description: description}) when is_binary(description), do: description
  defp journal_entry_label(_entry), do: "Ledger entry"

  defp match_status_variant(:accepted), do: :success
  defp match_status_variant(:rejected), do: :error
  defp match_status_variant(:superseded), do: :default
  defp match_status_variant(_), do: :warning

  defp rule_creatable?(%{review_status: :reviewed, category: category}) do
    category not in [nil, :unknown]
  end

  defp rule_creatable?(_transaction), do: false

  defp rule_name_from_transaction(transaction) do
    transaction
    |> bank_transaction_counterparty()
    |> then(&"#{&1} banking rule")
  end

  defp atom_param(value) when value in [nil, ""], do: nil
  defp atom_param(value) when is_atom(value), do: value
  defp atom_param(value) when is_binary(value), do: String.to_existing_atom(value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp format_metadata_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp error_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Exception.message()
  rescue
    _ -> "Could not update transaction."
  end
end
