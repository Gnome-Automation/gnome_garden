# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     GnomeGarden.Repo.insert!(%GnomeGarden.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias GnomeGarden.Agents.DefaultDeployments
alias GnomeGarden.Commercial.DefaultCompanyProfiles

company_profile = DefaultCompanyProfiles.ensure_default()
result = DefaultDeployments.ensure_defaults()

IO.puts("""
Seeded agent deployments.
Created: #{Enum.join(result.created, ", ")}
Existing: #{Enum.join(result.existing, ", ")}
""")

IO.puts("""
Seeded company profile.
Created: #{company_profile.created?}
Profile: #{company_profile.profile.name} (#{company_profile.profile.key})
""")
