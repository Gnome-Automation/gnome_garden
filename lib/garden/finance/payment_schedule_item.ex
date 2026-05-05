defmodule GnomeGarden.Finance.PaymentScheduleItem do
  @moduledoc """
  One installment in a fixed-fee payment schedule on an Agreement.

  A schedule is valid only when its items' percentages sum to 100.
  Items are ordered by `position` (1, 2, 3...) and each generates
  one draft Invoice when invoice generation is triggered.
  """

  use Ash.Resource,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  alias GnomeGarden.Finance.PaymentScheduleItem

  postgres do
    table "payment_schedule_items"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:agreement_id, :position, :label, :percentage, :due_days]
      validate PaymentScheduleItem.Validations.PercentageSumNotExceeded
    end

    update :update do
      require_atomic? false
      accept [:position, :label, :percentage, :due_days]
      validate PaymentScheduleItem.Validations.PercentageSumNotExceeded
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      description "Display order within the schedule (1, 2, 3...)."
    end

    attribute :label, :string do
      allow_nil? false
      description "Human label shown on invoice notes (e.g. 'Deposit', 'Milestone 1')."
    end

    attribute :percentage, :decimal do
      allow_nil? false
      description "Percentage of contract_value billed for this installment (e.g. 25.0)."
    end

    attribute :due_days, :integer do
      default 30
      allow_nil? false
      description "Days after invoice creation date when this installment is due."
    end

    timestamps()
  end

  relationships do
    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      allow_nil? false
    end
  end
end
