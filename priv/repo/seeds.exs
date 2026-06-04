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

# --- Company Documents ---
# Upsert W9 — idempotent, safe to re-run
existing_w9 =
  case GnomeGarden.Documents.list_active_documents() do
    {:ok, docs} -> Enum.find(docs, &(&1.name == "W9 Form"))
    _ -> nil
  end

unless existing_w9 do
  {:ok, _} =
    GnomeGarden.Documents.create_document(%{
      name: "W9 Form",
      description: "IRS Form W-9 — Request for Taxpayer Identification Number and Certification",
      category: :tax,
      version: "2024",
      file_path: "documents/w9-gnome-automation-signed.pdf",
      status: :active
    })

  IO.puts("Seeded: W9 Form (2024)")
end
