defmodule GnomeGarden.Agents.Tools.GitDiff do
  @moduledoc """
  Show git diff for working changes or between refs.
  """

  use Jido.Action,
    name: "git_diff",
    description: "Show git diff. Returns the diff output for staged, unstaged, or between refs.",
    schema: [
      ref: [
        type: :string,
        doc: "Git ref to compare (e.g. HEAD~1, main). If omitted, shows working changes."
      ],
      staged: [type: :boolean, default: false, doc: "Show only staged changes"],
      file: [type: :string, doc: "Limit diff to specific file"]
    ]

  @max_output_chars 15_000

  @impl true
  def run(params, _context) do
    args = build_args(params)

    case System.cmd("git", ["diff"] ++ args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, %{diff: truncate(output)}}

      {output, _} ->
        {:error, "git diff failed: #{String.trim(output)}"}
    end
  end

  defp build_args(params) do
    args = []
    staged = Map.get(params, :staged) || Map.get(params, "staged", false)
    ref = Map.get(params, :ref) || Map.get(params, "ref")
    file = Map.get(params, :file) || Map.get(params, "file")

    args = if staged, do: ["--cached" | args], else: args
    args = if ref, do: [ref | args], else: args
    args = if file, do: args ++ ["--", file], else: args

    args
  end

  defp truncate(output) when byte_size(output) > @max_output_chars do
    String.slice(output, 0, @max_output_chars) <> "\n... (diff truncated)"
  end

  defp truncate(output), do: output
end
