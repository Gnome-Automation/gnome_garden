defmodule GnomeGarden.Finance.RetainerTest do
  use GnomeGarden.DataCase, async: true
  alias GnomeGarden.Finance

  test "journal entry accepts :retainer_received entry type" do
    valid_types = [:retainer_received, :retainer_applied, :retainer_unapplied, :retainer_voided]

    for type <- valid_types do
      cs =
        GnomeGarden.Finance.JournalEntry
        |> Ash.Changeset.for_create(:create, %{
          date: Date.utc_today(),
          description: "test",
          entry_type: type,
          reference_type: "retainer"
        }, authorize?: false)

      refute Keyword.has_key?(cs.errors, :entry_type),
             "entry_type #{type} should be valid but got errors: #{inspect(cs.errors)}"
    end
  end

  test "creates a retainer with auto-generated number" do
    org = org_fixture()

    assert {:ok, retainer} =
      GnomeGarden.Finance.Retainer
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        amount: Decimal.new("500.00"),
        received_on: Date.utc_today()
      }, authorize?: false)
      |> Ash.create()

    assert retainer.retainer_number =~ ~r/^RET-\d{4}$/
    assert retainer.status == :draft
    assert retainer.auto_apply == false
  end

  test "state machine: draft → issued → paid → exhausted" do
    org = org_fixture()
    {:ok, retainer} = create_retainer(org, "200.00")

    {:ok, retainer} = Ash.update(retainer, %{}, action: :issue, authorize?: false)
    assert retainer.status == :issued

    {:ok, retainer} = Ash.update(retainer, %{}, action: :mark_paid, authorize?: false)
    assert retainer.status == :paid

    {:ok, retainer} = Ash.update(retainer, %{}, action: :exhaust, authorize?: false)
    assert retainer.status == :exhausted
  end

  test "void transitions from draft, issued, or paid" do
    org = org_fixture()

    for initial_status <- [:draft, :issued, :paid] do
      {:ok, retainer} = create_retainer_in_status(org, initial_status)
      {:ok, voided} = Ash.update(retainer, %{}, action: :void, authorize?: false)
      assert voided.status == :void
    end
  end

  test "reopen transitions from exhausted back to paid" do
    org = org_fixture()
    {:ok, retainer} = create_retainer_in_status(org, :paid)
    {:ok, retainer} = Ash.update(retainer, %{}, action: :exhaust, authorize?: false)
    assert retainer.status == :exhausted

    {:ok, retainer} = Ash.update(retainer, %{}, action: :reopen, authorize?: false)
    assert retainer.status == :paid
  end

  defp org_fixture do
    {:ok, org} =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{name: "Test Corp #{System.unique_integer()}"}, authorize?: false)
      |> Ash.create()
    org
  end

  defp create_retainer(org, amount \\ "500.00") do
    GnomeGarden.Finance.Retainer
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      amount: Decimal.new(amount),
      received_on: Date.utc_today()
    }, authorize?: false)
    |> Ash.create()
  end

  defp create_retainer_in_status(org, status) do
    {:ok, r} = create_retainer(org)
    case status do
      :draft -> {:ok, r}
      :issued -> Ash.update(r, %{}, action: :issue, authorize?: false)
      :paid ->
        {:ok, r} = Ash.update(r, %{}, action: :issue, authorize?: false)
        Ash.update(r, %{}, action: :mark_paid, authorize?: false)
    end
  end
end
