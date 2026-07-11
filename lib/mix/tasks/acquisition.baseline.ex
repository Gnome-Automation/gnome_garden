defmodule Mix.Tasks.Acquisition.Baseline do
  @shortdoc "Print the read-only acquisition maturity baseline"

  @moduledoc """
  Builds the acquisition maturity, yield, spend, and failure baseline through
  the `GnomeGarden.Acquisition.build_baseline/1` Ash code interface.

      mix acquisition.baseline

  The command is read-only and prints JSON suitable for comparison or archival.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_argv) do
    case GnomeGarden.Acquisition.build_baseline() do
      {:ok, report} -> Mix.shell().info(Jason.encode!(report, pretty: true))
      {:error, error} -> Mix.raise("Unable to build acquisition baseline: #{inspect(error)}")
    end
  end
end
