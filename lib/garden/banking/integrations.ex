defmodule GnomeGarden.Banking.Integrations do
  @moduledoc """
  Routes a `BankConnection` to its provider-specific sync adapter. Adding a new
  bank provider means adding a clause here and a `Banking.Integrations.<Provider>`
  module — no changes to the core Banking resources.
  """

  alias GnomeGarden.Banking.Integrations.Mercury

  @doc "Syncs a connection via its provider adapter."
  def sync(%{provider: :mercury} = connection), do: Mercury.sync(connection)
  def sync(%{provider: provider}), do: {:error, {:unsupported_provider, provider}}
end
