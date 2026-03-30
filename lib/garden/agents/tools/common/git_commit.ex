defmodule GnomeGarden.Agents.Tools.GitCommit do
  @moduledoc """
  Create a git commit with the staged changes.
  """

  use Jido.Action,
    name: "git_commit",
    description:
      "Create a git commit. Stage files first with git add, then commit with a message.",
    schema: [
      message: [type: :string, required: true, doc: "Commit message"],
      add_all: [
        type: :boolean,
        default: false,
        doc: "Stage all changes before committing (git add -A)"
      ]
    ]

  @impl true
  def run(params, _context) do
    message = Map.get(params, :message) || Map.get(params, "message")
    add_all = Map.get(params, :add_all) || Map.get(params, "add_all", false)

    # Optionally stage all changes
    if add_all do
      case System.cmd("git", ["add", "-A"], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, "git add failed: #{String.trim(output)}"}
      end
    end

    case System.cmd("git", ["commit", "-m", message], stderr_to_stdout: true) do
      {output, 0} ->
        # Get the commit hash
        {hash, _} = System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true)

        {:ok,
         %{
           message: message,
           hash: String.trim(hash),
           output: output
         }}

      {output, _} ->
        {:error, "git commit failed: #{String.trim(output)}"}
    end
  end
end
