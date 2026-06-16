defmodule GnomeGardenWeb.Commercial.CompanyFactsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration
  alias GnomeGarden.Company.RegistrationFacts

  @impl true
  def mount(_params, _session, socket) do
    DefaultRegistration.ensure_default()

    {:ok,
     socket
     |> assign(:page_title, "Company Profile")
     |> assign(:reveal_sensitive?, false)
     |> assign(:form_error, nil)
     |> load_facts()}
  end

  @impl true
  def handle_event("toggle_sensitive", _params, socket) do
    {:noreply,
     socket
     |> update(:reveal_sensitive?, &(!&1))
     |> load_facts()}
  end

  @impl true
  def handle_event("save_company", %{"company" => params}, socket) do
    profile = socket.assigns.profile
    metadata = update_company_metadata(profile.metadata || %{}, params)

    case Company.update_company_profile(profile, %{
           legal_name: blank_to_nil(params["legal_name"]),
           metadata: metadata
         }) do
      {:ok, _profile} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company facts saved.")
         |> assign(:form_error, nil)
         |> load_facts()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error_message(error))}
    end
  end

  @impl true
  def handle_event("save_tax_identifier", %{"tax_identifier" => params}, socket) do
    tax_identifier = socket.assigns.fein_identifier
    value = blank_to_nil(params["value"])

    result =
      cond do
        tax_identifier && value ->
          Company.rotate_company_tax_identifier_value(tax_identifier, %{value: value})

        tax_identifier ->
          Company.update_company_tax_identifier(tax_identifier, %{
            label: params["label"],
            status: :active,
            notes: params["notes"]
          })

        value ->
          Company.create_company_tax_identifier(%{
            company_profile_id: socket.assigns.profile.id,
            identifier_type: :fein,
            jurisdiction: "US",
            label: params["label"],
            value: value,
            status: :active,
            notes: params["notes"]
          })

        true ->
          {:error, "Enter an EIN to create the tax identifier."}
      end

    case result do
      {:ok, _identifier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tax identifier saved.")
         |> assign(:form_error, nil)
         |> load_facts()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error_message(error))}
    end
  end

  @impl true
  def handle_event("save_payment_destination", %{"payment_destination" => params}, socket) do
    destination = socket.assigns.payment_destination_record
    account_number = blank_to_nil(params["account_number"])
    attrs = payment_destination_attrs(params)

    result =
      cond do
        destination && account_number ->
          with {:ok, destination} <- Company.update_payment_destination(destination, attrs) do
            Company.rotate_payment_destination_account_number(destination, %{
              account_number: account_number
            })
          end

        destination ->
          Company.update_payment_destination(destination, attrs)

        account_number ->
          attrs
          |> Map.put(:key, "gnome_mercury_checking")
          |> Map.put(:account_number, account_number)
          |> Company.create_payment_destination()

        true ->
          {:error, "Enter an account number to create the payment destination."}
      end

    case result do
      {:ok, _destination} ->
        {:noreply,
         socket
         |> put_flash(:info, "Payment destination saved.")
         |> assign(:form_error, nil)
         |> load_facts()}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, error_message(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Company">
        Company Profile
        <:subtitle>
          Maintain the reusable business profile used for vendor portals, procurement registrations,
          and payee setup.
        </:subtitle>
        <:actions>
          <.button
            phx-click="toggle_sensitive"
            variant={if(@reveal_sensitive?, do: "primary", else: nil)}
          >
            {if(@reveal_sensitive?, do: "Hide Sensitive", else: "Reveal Sensitive")}
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
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <.profile_stat label="Legal entity" value={@company.legal_entity_name} />
          <.profile_stat label="Tax identifier" value={tax_status_label(@fein_identifier)} />
          <.profile_stat
            label="Payment account"
            value={payment_account_display(@payment_destination)}
          />
          <.profile_stat label="Documents" value={"#{length(@company_documents)} on file"} />
        </div>

        <div class="sticky top-0 z-10 -mx-4 overflow-x-auto border-y border-base-content/10 bg-base-100/95 px-4 py-2 backdrop-blur sm:static sm:mx-0 sm:rounded-lg sm:border">
          <div class="flex min-w-max gap-2">
            <.profile_nav href="#legal-entity">Legal</.profile_nav>
            <.profile_nav href="#people-contacts">People & Contacts</.profile_nav>
            <.profile_nav href="#tax">Tax</.profile_nav>
            <.profile_nav href="#accounts">Accounts</.profile_nav>
            <.profile_nav href="#documents">Documents</.profile_nav>
            <.profile_nav href="#compliance">Compliance</.profile_nav>
            <.profile_nav href="#sources">Sources</.profile_nav>
          </div>
        </div>

        <.section
          title="Reusable Registration Profile"
          description="Default answers that should apply across vendor portals and procurement registrations."
        >
          <form id="company-facts-form" phx-submit="save_company" class="space-y-6">
            <.profile_panel
              id="legal-entity"
              title="Legal entity"
              description="Registered identity and address. Customer-specific packet fields stay with the customer onboarding record."
            >
              <div class="grid gap-4 md:grid-cols-2">
                <.input
                  name="company[legal_name]"
                  label="Legal entity name"
                  value={@company.legal_entity_name}
                  required
                />
                <.input name="company[telephone]" label="Telephone" value={@company.telephone} />
              </div>

              <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
                <.input
                  name="company[address_street]"
                  label="Registered street"
                  value={@registered_address["street"]}
                />
                <.input name="company[address_city]" label="City" value={@registered_address["city"]} />
                <.input
                  name="company[address_state]"
                  label="State"
                  value={@registered_address["state"]}
                />
                <.input
                  name="company[address_postal_code]"
                  label="Postcode"
                  value={@registered_address["postal_code"]}
                />
                <.input
                  name="company[country]"
                  label="Country"
                  value={@registered_address["country"]}
                />
              </div>

              <div class="grid gap-3 md:grid-cols-3">
                <.profile_fact
                  label="Entity type"
                  value={@legal_entity_metadata["entity_type"] || "LLC"}
                />
                <.profile_fact
                  label="Signing authority"
                  value={
                    get_in(@legal_entity_metadata, ["signing_authority", "title"]) ||
                      "Managing Member"
                  }
                />
                <.profile_fact
                  label="Registered agent"
                  value={registered_agent_label(@registered_agent)}
                />
              </div>
            </.profile_panel>

            <.profile_panel
              id="people-contacts"
              title="People & contacts"
              description="Members are listed first; vendor contact can be either member depending on the registration."
            >
              <div class="grid gap-4 lg:grid-cols-2">
                <div
                  :for={{member, index} <- Enum.with_index(@members)}
                  class="rounded-lg border border-base-content/10 bg-base-200/50 p-3"
                >
                  <input type="hidden" name={"company[member_#{index}_key]"} value={member["key"]} />
                  <div class="text-xs font-semibold uppercase text-base-content/50">
                    LLC member
                  </div>
                  <div class="mt-3 grid gap-3 md:grid-cols-2">
                    <.input
                      name={"company[member_#{index}_name]"}
                      label="Name"
                      value={member["name"]}
                    />
                    <.input
                      name={"company[member_#{index}_title]"}
                      label="Title"
                      value={member["title"]}
                    />
                    <.input
                      name={"company[member_#{index}_phone]"}
                      label="Direct phone"
                      value={member["direct_phone"]}
                    />
                    <.input
                      name={"company[member_#{index}_email]"}
                      label="Email"
                      type="email"
                      value={member["email"]}
                    />
                  </div>
                </div>
              </div>

              <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                <.input
                  name="company[vendor_contact_member_key]"
                  label="Vendor contact"
                  type="select"
                  value={@vendor_contact_member_key}
                  options={member_contact_options(@members)}
                />
                <.input
                  name="company[vendor_contact_phone]"
                  label="Direct phone"
                  value={@vendor_contact["direct_phone"]}
                />
                <.input
                  name="company[vendor_contact_email]"
                  label="Contact email"
                  type="email"
                  value={@vendor_contact["email"]}
                />
                <.input
                  name="company[order_email]"
                  label="Orders email"
                  type="email"
                  value={@company.order_email}
                />
                <.input
                  name="company[purchasing_email]"
                  label="Purchasing email"
                  type="email"
                  value={@company.purchasing_email}
                />
                <.input
                  name="company[finance_email]"
                  label="Finance email"
                  type="email"
                  value={@company.finance_email}
                />
              </div>
            </.profile_panel>

            <.profile_panel
              id="terms"
              title="Default commercial terms"
              description="Reusable defaults only. Customer-mandated terms remain on that onboarding packet."
            >
              <div class="grid gap-4 md:grid-cols-3">
                <.input
                  name="company[delivery_terms]"
                  label="Delivery terms"
                  value={term_value(@standard_terms, "delivery_terms")}
                />
                <.input
                  name="company[payment_terms]"
                  label="Payment terms"
                  value={term_value(@standard_terms, "payment_terms")}
                />
                <.input name="company[currency]" label="Currency" value={@standard_terms["currency"]} />
              </div>
            </.profile_panel>

            <div class="flex justify-end">
              <.button type="submit" variant="primary" phx-disable-with="Saving...">
                Save Registration Profile
              </.button>
            </div>
          </form>
        </.section>

        <div class="grid gap-5 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
          <.section
            title="Tax"
            description="Encrypted identifiers and non-US default answers used on vendor forms."
          >
            <form id="tax-identifier-form" phx-submit="save_tax_identifier" class="space-y-4">
              <div id="tax" class="grid gap-4 md:grid-cols-2 xl:grid-cols-1">
                <.input
                  name="tax_identifier[label]"
                  label="Identifier"
                  value={
                    (@fein_identifier && @fein_identifier.label) ||
                      "Federal Employer Identification Number"
                  }
                />
                <.input
                  name="tax_identifier[value]"
                  label="FEIN"
                  value={@facts.tax_identifiers[:fein_us] && @facts.tax_identifiers.fein_us.value}
                  placeholder={masked_value(@fein_identifier && @fein_identifier.value_last4)}
                />
                <.input
                  name="tax_identifier[notes]"
                  label="Notes"
                  value={@fein_identifier && @fein_identifier.notes}
                />
              </div>

              <div class="grid gap-3 md:grid-cols-3 xl:grid-cols-1">
                <.profile_fact label="EU VAT" value={tax_metadata_value(@tax_metadata, "vat_eu")} />
                <.profile_fact
                  label="India GST"
                  value={tax_metadata_value(@tax_metadata, "gst_india")}
                />
                <.profile_fact
                  label="India PAN"
                  value={tax_metadata_value(@tax_metadata, "pan_india")}
                />
              </div>

              <div class="flex justify-end">
                <.button type="submit" variant="primary" phx-disable-with="Saving...">
                  Save Tax Identifier
                </.button>
              </div>
            </form>
          </.section>

          <.section
            title="Accounts"
            description="Current Mercury/Column destination for ACH, domestic wires, and international wires."
          >
            <form
              id="payment-destination-form"
              phx-submit="save_payment_destination"
              class="space-y-5"
            >
              <div id="accounts" class="grid gap-3 md:grid-cols-3">
                <.profile_fact label="Account" value={@payment_destination.label} />
                <.profile_fact
                  label="Account number"
                  value={payment_account_display(@payment_destination)}
                />
                <.profile_fact label="Currency" value={@payment_destination.currency_code || "USD"} />
              </div>

              <div class="grid gap-4 md:grid-cols-2">
                <.input
                  name="payment_destination[label]"
                  label="Account label"
                  value={@payment_destination.label}
                />
                <.input
                  name="payment_destination[account_number]"
                  label="Account number"
                  value={@payment_destination.account_number}
                  placeholder={masked_value(@payment_destination.account_number_last4)}
                />
                <.input
                  name="payment_destination[beneficiary_name]"
                  label="Beneficiary name"
                  value={@payment_destination.beneficiary_name}
                />
                <.input
                  name="payment_destination[bank_name]"
                  label="Bank name"
                  value={@payment_destination.bank_name}
                />
              </div>

              <div class="grid gap-4 md:grid-cols-3">
                <.input
                  name="payment_destination[domestic_routing_number]"
                  label="ACH routing number"
                  value={@payment_destination.domestic_routing_number}
                />
                <.input
                  name="payment_destination[wire_routing_number]"
                  label="Wire routing number"
                  value={@payment_destination.wire_routing_number}
                />
                <.input
                  name="payment_destination[alternate_routing_number]"
                  label="Alternate routing number"
                  value={@payment_destination.alternate_routing_number}
                />
              </div>

              <div class="grid gap-4 md:grid-cols-3">
                <.input
                  name="payment_destination[swift_bic]"
                  label="SWIFT / BIC"
                  value={@payment_destination.swift_bic}
                />
                <.input
                  name="payment_destination[intermediary_swift_bic]"
                  label="Intermediary SWIFT / BIC"
                  value={@payment_destination.intermediary_swift_bic}
                />
                <.input
                  name="payment_destination[currency_code]"
                  label="Currency"
                  value={@payment_destination.currency_code || "USD"}
                />
              </div>

              <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <.input
                  name="payment_destination[bank_street]"
                  label="Bank street"
                  value={@bank_address["street"]}
                />
                <.input
                  name="payment_destination[bank_city]"
                  label="Bank city"
                  value={@bank_address["city"]}
                />
                <.input
                  name="payment_destination[bank_state]"
                  label="Bank state"
                  value={@bank_address["state"]}
                />
                <.input
                  name="payment_destination[bank_postal_code]"
                  label="Bank postcode"
                  value={@bank_address["postal_code"]}
                />
              </div>

              <div class="flex justify-end">
                <.button type="submit" variant="primary" phx-disable-with="Saving...">
                  Save Account
                </.button>
              </div>
            </form>
          </.section>
        </div>

        <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
          <.section
            title="Documents"
            description="Reusable Gnome-owned files. Customer-specific forms belong on vendor onboarding."
          >
            <div id="documents" class="space-y-3">
              <.document_row :for={document <- @company_documents} document={document} />
              <div
                :if={@company_documents == []}
                class="rounded-lg border border-dashed border-base-content/20 p-4 text-sm text-base-content/60"
              >
                No reusable company documents have been attached yet.
              </div>
            </div>
          </.section>

          <.section
            title="Compliance"
            description="Company-level obligations that need review before becoming first-class checklist records."
          >
            <div id="compliance" class="space-y-3">
              <.compliance_row label="BOI report" value={compliance_summary(@compliance, "boi")} />
              <.compliance_row
                label="Annual checklist"
                value={compliance_summary(@compliance, "annual")}
              />
              <.compliance_row label="Formation" value={formation_summary(@formation)} />
              <.compliance_row
                label="Registered agent"
                value={registered_agent_label(@registered_agent)}
              />
            </div>
          </.section>
        </div>

        <.section
          title="Source Review"
          description="Where current values came from and what should be checked before changing operational records."
        >
          <div id="sources" class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <.source_card
              title="High confidence"
              value="W-9, registered agent, milestones, BOI status"
            />
            <.source_card
              title="Needs review"
              value="Company profile boilerplate, business rates, licenses"
            />
            <.source_card
              title="Conflict"
              value="Older Relayfi notes should not replace Mercury/Column account data"
            />
            <.source_card
              title="Missing"
              value="CP 575 document and BOI confirmation number still need locating"
            />
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp profile_stat(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200 px-3 py-3">
      <div class="text-[11px] font-semibold uppercase text-base-content/50">{@label}</div>
      <div class="mt-1 break-words text-sm font-semibold text-base-content">{@value || "-"}</div>
    </div>
    """
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  defp profile_nav(assigns) do
    ~H"""
    <a
      href={@href}
      class="rounded-md border border-base-content/10 bg-base-200 px-3 py-2 text-sm font-semibold text-base-content/75 hover:bg-base-300 hover:text-base-content"
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  slot :inner_block, required: true

  defp profile_panel(assigns) do
    ~H"""
    <section id={@id} class="space-y-4 scroll-mt-24 rounded-lg border border-base-content/10 p-4">
      <div>
        <h3 class="text-base font-semibold text-base-content">{@title}</h3>
        <p class="mt-1 text-sm leading-5 text-base-content/60">{@description}</p>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil

  defp profile_fact(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/60 px-3 py-2.5">
      <div class="text-[11px] font-semibold uppercase text-base-content/50">{@label}</div>
      <div class="mt-1 break-words text-sm font-medium text-base-content">{@value || "-"}</div>
    </div>
    """
  end

  attr :document, :any, required: true

  defp document_row(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 p-3">
      <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <h3 class="text-sm font-semibold text-base-content">{@document.title}</h3>
          <p class="mt-1 text-xs text-base-content/60">
            {document_kind_label(@document.kind)} · {String.capitalize(to_string(@document.status))}
          </p>
        </div>
        <span class="rounded-md bg-base-200 px-2 py-1 text-xs font-semibold text-base-content/70">
          {document_date_label(@document)}
        </span>
      </div>
      <p :if={@document.description} class="mt-2 text-sm leading-5 text-base-content/70">
        {@document.description}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp compliance_row(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 rounded-lg border border-base-content/10 px-3 py-2.5 sm:flex-row sm:items-center sm:justify-between">
      <div class="text-sm font-semibold text-base-content">{@label}</div>
      <div class="text-sm text-base-content/65 sm:text-right">{@value || "Needs review"}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true

  defp source_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-200/50 p-3">
      <div class="text-xs font-semibold uppercase text-base-content/50">{@title}</div>
      <p class="mt-2 text-sm leading-5 text-base-content/75">{@value}</p>
    </div>
    """
  end

  defp load_facts(socket) do
    profile = DefaultRegistration.ensure_default().profile

    {:ok, facts} =
      RegistrationFacts.resolve(reveal_sensitive?: socket.assigns.reveal_sensitive?)

    tax_identifiers = elem(Company.list_company_tax_identifiers_for_profile(profile.id), 1)
    payment_destination_record = payment_destination_record()
    company_documents = company_documents(profile.id)

    company = facts.company
    members = normalize_members(Map.get(company, :members, []))
    payment_destination = payment_destination_defaults(facts.payment_destination)
    metadata = profile.metadata || %{}
    vendor_registration = Map.get(metadata, "vendor_registration", %{})

    assign(socket,
      profile: profile,
      facts: facts,
      company: company,
      vendor_contact: company.vendor_contact || %{},
      members: members,
      vendor_contact_member_key: vendor_contact_member_key(company.vendor_contact, members),
      registered_address: company.registered_address || %{},
      standard_terms: facts.standard_terms || %{},
      tax_metadata: Map.get(vendor_registration, "tax_identifiers", %{}),
      legal_entity_metadata: Map.get(vendor_registration, "company", %{}),
      fein_identifier: Enum.find(tax_identifiers, &(&1.identifier_type == :fein)),
      payment_destination_record: payment_destination_record,
      payment_destination: payment_destination,
      bank_address: Map.get(payment_destination, :bank_address, %{}),
      company_documents: company_documents,
      compliance: Map.get(metadata, "compliance", %{}),
      formation: Map.get(metadata, "formation", %{}),
      registered_agent: Map.get(metadata, "registered_agent", %{})
    )
  end

  defp company_documents(profile_id) do
    case Company.list_company_documents_for_profile(profile_id) do
      {:ok, documents} -> documents
      {:error, _reason} -> []
    end
  end

  defp payment_destination_record do
    case Company.get_payment_destination_by_key("gnome_mercury_checking") do
      {:ok, destination} -> destination
      {:error, _reason} -> nil
    end
  end

  defp payment_destination_defaults(nil) do
    %{
      key: "gnome_mercury_checking",
      label: "Gnome Mercury Checking",
      provider: :mercury,
      account_kind: :checking,
      beneficiary_name: "Gnome Automation LLC",
      beneficiary_address: %{
        "street" => "2108 N Street, Ste N",
        "city" => "Sacramento",
        "state" => "CA",
        "postal_code" => "95816",
        "country" => "US"
      },
      bank_name: "Column N.A.",
      bank_address: %{
        "street" => "1 Letterman Drive, Building A, Suite A4-700",
        "city" => "San Francisco",
        "state" => "CA",
        "postal_code" => "94129",
        "country" => "US"
      },
      domestic_routing_number: "121145433",
      wire_routing_number: "121145433",
      alternate_routing_number: "121145307",
      swift_bic: "CLNOUS66MER",
      intermediary_swift_bic: "CHASUS33XXX",
      currency_code: "USD",
      account_number_present: false,
      account_number_last4: nil,
      account_number: nil
    }
  end

  defp payment_destination_defaults(destination), do: destination

  defp update_company_metadata(metadata, params) do
    vendor_registration = Map.get(metadata, "vendor_registration", %{})
    company = Map.get(vendor_registration, "company", %{})
    standard_terms = Map.get(vendor_registration, "standard_terms", %{})
    members = member_params(params)
    vendor_contact = vendor_contact_params(params, members)

    company =
      Map.merge(company, %{
        "legal_entity_name" => blank_to_nil(params["legal_name"]),
        "telephone" => blank_to_nil(params["telephone"]),
        "order_email" => blank_to_nil(params["order_email"]),
        "purchasing_email" => blank_to_nil(params["purchasing_email"]),
        "finance_email" => blank_to_nil(params["finance_email"]),
        "members" => members,
        "registered_address" => %{
          "street" => blank_to_nil(params["address_street"]),
          "city" => blank_to_nil(params["address_city"]),
          "state" => blank_to_nil(params["address_state"]),
          "postal_code" => blank_to_nil(params["address_postal_code"]),
          "country" => blank_to_nil(params["country"])
        },
        "vendor_contact" => vendor_contact
      })

    standard_terms =
      Map.merge(standard_terms, %{
        "delivery_terms" => %{"default_answer" => blank_to_nil(params["delivery_terms"])},
        "payment_terms" => %{"default_answer" => blank_to_nil(params["payment_terms"])},
        "currency" => blank_to_nil(params["currency"])
      })

    put_in(metadata, ["vendor_registration"], %{
      vendor_registration
      | "company" => company,
        "standard_terms" => standard_terms
    })
  end

  defp payment_destination_attrs(params) do
    %{
      label: blank_to_nil(params["label"]) || "Gnome Mercury Checking",
      provider: :mercury,
      status: :active,
      account_kind: :checking,
      beneficiary_name: blank_to_nil(params["beneficiary_name"]) || "Gnome Automation LLC",
      beneficiary_address: %{
        "street" => "2108 N Street, Ste N",
        "city" => "Sacramento",
        "state" => "CA",
        "postal_code" => "95816",
        "country" => "US"
      },
      bank_name: blank_to_nil(params["bank_name"]) || "Column N.A.",
      bank_address: %{
        "street" => blank_to_nil(params["bank_street"]),
        "city" => blank_to_nil(params["bank_city"]),
        "state" => blank_to_nil(params["bank_state"]),
        "postal_code" => blank_to_nil(params["bank_postal_code"]),
        "country" => "US"
      },
      domestic_routing_number: blank_to_nil(params["domestic_routing_number"]),
      wire_routing_number: blank_to_nil(params["wire_routing_number"]),
      alternate_routing_number: blank_to_nil(params["alternate_routing_number"]),
      swift_bic: blank_to_nil(params["swift_bic"]),
      intermediary_swift_bic: blank_to_nil(params["intermediary_swift_bic"]),
      currency_code: blank_to_nil(params["currency_code"]) || "USD"
    }
  end

  defp default_members do
    [
      %{
        "key" => "bassam_hammoud",
        "name" => "Bassam Hammoud",
        "title" => "Co-Founder",
        "direct_phone" => nil,
        "email" => "bhammoud@gnomeautomation.com",
        "vendor_contact_eligible" => true
      },
      %{
        "key" => "patrick_curran",
        "name" => "Patrick Curran",
        "title" => "Co-Founder",
        "direct_phone" => "970-556-4676",
        "email" => "pc@gnomeautomation.com",
        "vendor_contact_eligible" => true
      }
    ]
  end

  defp member_params(params) do
    0..1
    |> Enum.map(fn index ->
      %{
        "key" => blank_to_nil(params["member_#{index}_key"]) || default_member_key(index),
        "name" => blank_to_nil(params["member_#{index}_name"]),
        "title" => blank_to_nil(params["member_#{index}_title"]),
        "direct_phone" => blank_to_nil(params["member_#{index}_phone"]),
        "email" => blank_to_nil(params["member_#{index}_email"]),
        "vendor_contact_eligible" => true
      }
    end)
    |> Enum.reject(&(is_nil(&1["name"]) and is_nil(&1["email"])))
  end

  defp default_member_key(0), do: "bassam_hammoud"
  defp default_member_key(1), do: "patrick_curran"
  defp default_member_key(index), do: "member_#{index}"

  defp normalize_members([]), do: default_members()
  defp normalize_members(members) when is_list(members), do: members
  defp normalize_members(_members), do: default_members()

  defp vendor_contact_params(params, members) do
    member_key = blank_to_nil(params["vendor_contact_member_key"])
    selected_member = Enum.find(members, &(&1["key"] == member_key)) || List.first(members) || %{}

    %{
      "member_key" => selected_member["key"],
      "name" => selected_member["name"],
      "direct_phone" =>
        blank_to_nil(params["vendor_contact_phone"]) || selected_member["direct_phone"],
      "email" => blank_to_nil(params["vendor_contact_email"]) || selected_member["email"]
    }
  end

  defp member_contact_options(members) do
    Enum.map(members, fn member ->
      {member["name"] || member["email"] || member["key"], member["key"]}
    end)
  end

  defp vendor_contact_member_key(nil, members), do: first_member_key(members)

  defp vendor_contact_member_key(%{"member_key" => member_key}, members)
       when is_binary(member_key) and member_key != "" do
    if Enum.any?(members || [], &(&1["key"] == member_key)) do
      member_key
    else
      first_member_key(members)
    end
  end

  defp vendor_contact_member_key(%{"name" => name}, members) when is_binary(name) do
    members
    |> Kernel.||([])
    |> Enum.find(&(String.downcase(&1["name"] || "") == String.downcase(name)))
    |> case do
      nil -> first_member_key(members)
      member -> member["key"]
    end
  end

  defp vendor_contact_member_key(_vendor_contact, members), do: first_member_key(members)

  defp first_member_key([%{"key" => key} | _]), do: key
  defp first_member_key(_members), do: nil

  defp masked_value(nil), do: nil
  defp masked_value(""), do: nil
  defp masked_value(last4), do: "Stored ending #{last4}"

  defp term_value(standard_terms, key) do
    standard_terms
    |> Map.get(key, %{})
    |> Map.get("default_answer")
  end

  defp payment_account_display(%{account_number: value}) when is_binary(value), do: value
  defp payment_account_display(%{account_number_last4: last4}), do: masked_value(last4) || "-"
  defp payment_account_display(_payment_destination), do: "-"

  defp tax_status_label(nil), do: "Needs EIN"
  defp tax_status_label(%{value_present: true, value_last4: last4}), do: masked_value(last4)
  defp tax_status_label(%{status: status}) when not is_nil(status), do: status_label(status)
  defp tax_status_label(_identifier), do: "Needs review"

  defp tax_metadata_value(metadata, key) do
    metadata
    |> Map.get(key, %{})
    |> case do
      %{"value" => value} ->
        value

      %{"status" => status, "last4" => last4} when not is_nil(last4) ->
        "#{status}, ending #{last4}"

      %{"status" => status} ->
        status

      _ ->
        nil
    end
  end

  defp registered_agent_label(%{"name" => name}) when is_binary(name), do: name
  defp registered_agent_label(%{"service" => name}) when is_binary(name), do: name
  defp registered_agent_label(%{"registered_agent" => name}) when is_binary(name), do: name
  defp registered_agent_label(%{"agent" => name}) when is_binary(name), do: name
  defp registered_agent_label(name) when is_binary(name), do: name
  defp registered_agent_label(_registered_agent), do: "Needs review"

  defp compliance_summary(compliance, key) do
    compliance
    |> Map.get(key, %{})
    |> case do
      %{"status" => status, "filed_on" => filed_on} when not is_nil(filed_on) ->
        "#{status_label(status)} on #{filed_on}"

      %{"status" => status, "completed_on" => completed_on} when not is_nil(completed_on) ->
        "#{status_label(status)} on #{completed_on}"

      %{"status" => status} ->
        status_label(status)

      %{"summary" => summary} ->
        summary

      value when is_binary(value) ->
        value

      _ ->
        nil
    end
  end

  defp formation_summary(%{} = formation) when map_size(formation) > 0 do
    formed_on = formation["formed_on"] || formation["formation_date"] || formation["filed_on"]
    state = formation["state"] || formation["jurisdiction"] || "CA"

    if formed_on do
      "Formed #{formed_on} in #{state}"
    else
      "Formation metadata captured"
    end
  end

  defp formation_summary(_formation), do: nil

  defp document_kind_label(kind) do
    kind
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp document_date_label(%{expires_on: %Date{} = date}), do: "Expires #{Date.to_iso8601(date)}"
  defp document_date_label(%{signed_on: %Date{} = date}), do: "Signed #{Date.to_iso8601(date)}"

  defp document_date_label(%{effective_on: %Date{} = date}),
    do: "Effective #{Date.to_iso8601(date)}"

  defp document_date_label(_document), do: "No date"

  defp status_label(status) when is_atom(status), do: status |> to_string() |> status_label()

  defp status_label(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_label(status), do: to_string(status)

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
