defmodule GnomeGarden.Sales.Opportunity do
  @moduledoc """
  Opportunity resource for CRM.

  Represents sales pipeline opportunities/deals.
  Can be created from Bids or directly for prospect outreach.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :stage, :amount, :probability, :expected_close_date, :inserted_at]
  end

  postgres do
    table "opportunities"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :description,
        :stage,
        :amount,
        :probability,
        :expected_close_date,
        :source,
        :owner_id,
        :company_id,
        :primary_contact_id,
        :bid_id
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :stage,
        :amount,
        :probability,
        :expected_close_date,
        :actual_close_date,
        :source,
        :loss_reason,
        :owner_id,
        :primary_contact_id
      ]
    end

    update :advance_stage do
      argument :stage, :atom, allow_nil?: false
      change set_attribute(:stage, arg(:stage))
    end

    update :close_won do
      accept []
      change set_attribute(:stage, :closed_won)
      change set_attribute(:actual_close_date, &Date.utc_today/0)
      change set_attribute(:probability, 100)
    end

    update :close_lost do
      argument :loss_reason, :string, allow_nil?: false
      change set_attribute(:stage, :closed_lost)
      change set_attribute(:actual_close_date, &Date.utc_today/0)
      change set_attribute(:probability, 0)
      change set_attribute(:loss_reason, arg(:loss_reason))
    end

    read :by_owner do
      argument :owner_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:owner_id) and stage not in [:closed_won, :closed_lost])
      prepare build(sort: [expected_close_date: :asc])
    end

    read :by_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
      prepare build(sort: [inserted_at: :desc])
    end

    read :by_stage do
      argument :stage, :atom, allow_nil?: false
      filter expr(stage == ^arg(:stage))
      prepare build(sort: [expected_close_date: :asc])
    end

    read :pipeline do
      filter expr(stage not in [:closed_won, :closed_lost])
      prepare build(sort: [expected_close_date: :asc])
    end

    read :closing_soon do
      argument :days, :integer, default: 30
      filter expr(
               stage not in [:closed_won, :closed_lost] and
                 not is_nil(expected_close_date) and
                 expected_close_date < from_now(^arg(:days), :day)
             )
      prepare build(sort: [expected_close_date: :asc])
    end

    read :won do
      filter expr(stage == :closed_won)
      prepare build(sort: [actual_close_date: :desc])
    end

    read :lost do
      filter expr(stage == :closed_lost)
      prepare build(sort: [actual_close_date: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Opportunity name"
    end

    attribute :description, :string do
      public? true
      description "Detailed description"
    end

    attribute :stage, :atom do
      default :discovery
      public? true
      constraints one_of: [:discovery, :qualification, :demo, :proposal, :negotiation, :closed_won, :closed_lost]
      description "Pipeline stage"
    end

    attribute :amount, :decimal do
      public? true
      description "Deal value in dollars"
    end

    attribute :probability, :integer do
      default 10
      public? true
      description "Win probability 0-100"
    end

    attribute :expected_close_date, :date do
      public? true
      description "Expected close date"
    end

    attribute :actual_close_date, :date do
      public? true
      description "Actual close date"
    end

    attribute :source, :atom do
      public? true
      constraints one_of: [:bid, :prospect, :referral, :inbound, :outbound, :other]
      description "Lead source"
    end

    attribute :loss_reason, :string do
      public? true
      description "Reason for losing (if closed_lost)"
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, GnomeGarden.Accounts.User do
      public? true
      description "User who owns this opportunity"
    end

    belongs_to :company, GnomeGarden.Sales.Company do
      allow_nil? false
      public? true
      description "Company this opportunity is for"
    end

    belongs_to :primary_contact, GnomeGarden.Sales.Contact do
      public? true
      description "Primary contact for this opportunity"
    end

    belongs_to :bid, GnomeGarden.Agents.Bid do
      public? true
      description "Source bid if created from a bid"
    end
  end

  calculations do
    calculate :weighted_amount, :decimal, expr(amount * probability / 100) do
      description "Weighted deal value"
    end
  end
end
