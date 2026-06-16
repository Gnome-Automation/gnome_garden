defmodule GnomeGarden.Finance.Integrations do
  @moduledoc """
  Provider adapter lookup for Finance banking integrations.

  Adapters fetch remote data only. Finance actions own persistence and business
  state transitions.
  """

  @default_adapters %{
    mercury: GnomeGarden.Finance.Integrations.Mercury
  }

  @spec adapter(atom()) :: module()
  def adapter(provider) do
    configured =
      Application.get_env(:gnome_garden, :finance_banking_adapters, [])
      |> Map.new()

    Map.get(configured, provider) || Map.fetch!(@default_adapters, provider)
  end
end
