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

result = DefaultDeployments.ensure_defaults()

IO.puts("""
Seeded agent deployments.
Created: #{Enum.join(result.created, ", ")}
Existing: #{Enum.join(result.existing, ", ")}
""")
