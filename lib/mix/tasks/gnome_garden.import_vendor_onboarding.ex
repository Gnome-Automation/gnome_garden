defmodule Mix.Tasks.GnomeGarden.ImportVendorOnboarding do
  @moduledoc """
  Imports company vendor-onboarding facts and customer onboarding records.

      mix gnome_garden.import_vendor_onboarding /secure/path/vendor-onboarding.json

  The JSON may contain banking details, so keep the file outside source control.
  In a release, prefer `GnomeGarden.Release.import_vendor_onboarding!/1`.
  """

  use Mix.Task

  alias GnomeGarden.Company

  @shortdoc "Import vendor-onboarding company/customer data from JSON"
  @requirements ["app.start"]

  @impl Mix.Task
  def run([path]) do
    payload = path |> File.read!() |> Jason.decode!()
    {:ok, result} = Company.import_vendor_onboarding(payload, authorize?: false)

    Mix.shell().info("""
    Imported vendor-onboarding profile.
    Company profile id: #{result["company_profile_id"]}
    Customers touched: #{result["customer_count"]}
    """)
  end

  def run(_args) do
    Mix.raise(
      "Usage: mix gnome_garden.import_vendor_onboarding /secure/path/vendor-onboarding.json"
    )
  end
end
