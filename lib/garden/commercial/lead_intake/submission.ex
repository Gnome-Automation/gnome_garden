defmodule GnomeGarden.Commercial.LeadIntake.Submission do
  @moduledoc """
  Embedded Ash form resource for manual referral lead intake.

  The resource is not persisted. It gives AshPhoenix a real action source,
  typed fields, validations, and nested embedded forms for multi-record intake.
  On successful form submission, callers pass the resulting struct to
  `to_lead_attrs/1` and persist through `GnomeGarden.Commercial.create_referral_lead/2`.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  alias GnomeGarden.Commercial.LeadIntake

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:organization, :sites, :contacts, :signal, :task]
      validate present([:organization, :signal])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization, LeadIntake.OrganizationInput do
      allow_nil? false
      public? true
    end

    attribute :sites, {:array, LeadIntake.SiteInput} do
      allow_nil? false
      default []
      public? true
    end

    attribute :contacts, {:array, LeadIntake.ContactInput} do
      allow_nil? false
      default []
      public? true
    end

    attribute :signal, LeadIntake.SignalInput do
      allow_nil? false
      public? true
    end

    attribute :task, LeadIntake.TaskInput do
      public? true
    end
  end

  @spec to_lead_attrs(struct()) :: map()
  def to_lead_attrs(submission) do
    %{
      organization: embedded_to_map(submission.organization),
      sites: Enum.map(submission.sites || [], &embedded_to_map/1),
      contacts: Enum.map(submission.contacts || [], &embedded_to_map/1),
      signal: signal_attrs(submission.signal),
      task: task_attrs(submission.task)
    }
  end

  defp signal_attrs(signal) do
    signal
    |> embedded_to_map()
    |> then(fn attrs ->
      suspected_needs = Map.get(attrs, :suspected_needs, []) |> split_lines()

      attrs
      |> Map.put(:metadata, %{"suspected_needs" => suspected_needs})
      |> Map.put(:suspected_needs, suspected_needs)
    end)
  end

  defp task_attrs(nil), do: nil

  defp task_attrs(task) do
    task
    |> embedded_to_map()
    |> case do
      %{title: title} = attrs when is_binary(title) and title != "" -> attrs
      _attrs -> nil
    end
  end

  defp embedded_to_map(nil), do: %{}

  defp embedded_to_map(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([
      :id,
      :__meta__,
      :__metadata__,
      :__lateral_join_source__,
      :aggregates,
      :calculations
    ])
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp split_lines(values) when is_list(values) do
    values
    |> Enum.flat_map(&split_lines/1)
    |> Enum.uniq()
  end

  defp split_lines(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&blank?/1)
  end

  defp split_lines(_value), do: []

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?([]), do: true
  defp blank?(%{} = value), do: map_size(value) == 0
  defp blank?(_value), do: false
end
