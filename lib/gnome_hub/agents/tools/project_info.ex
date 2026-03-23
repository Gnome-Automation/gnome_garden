defmodule GnomeHub.Agents.Tools.ProjectInfo do
  @moduledoc """
  Get information about the current project.

  Detects project type, structure, and relevant configuration.
  """

  use Jido.Action,
    name: "project_info",
    description: "Get information about the current project. Detects project type, structure, and configuration.",
    schema: [
      path: [type: :string, default: ".", doc: "Project root path"]
    ]

  @impl true
  def run(params, _context) do
    path = Map.get(params, :path) || Map.get(params, "path", ".")

    info = %{
      path: Path.expand(path),
      type: detect_type(path),
      files: count_files(path),
      git: git_info(path)
    }

    {:ok, info}
  end

  defp detect_type(path) do
    cond do
      File.exists?(Path.join(path, "mix.exs")) -> :elixir
      File.exists?(Path.join(path, "package.json")) -> :nodejs
      File.exists?(Path.join(path, "Cargo.toml")) -> :rust
      File.exists?(Path.join(path, "go.mod")) -> :go
      File.exists?(Path.join(path, "requirements.txt")) -> :python
      File.exists?(Path.join(path, "pyproject.toml")) -> :python
      File.exists?(Path.join(path, "Gemfile")) -> :ruby
      true -> :unknown
    end
  end

  defp count_files(path) do
    try do
      Path.wildcard(Path.join(path, "**/*"))
      |> Enum.reject(&File.dir?/1)
      |> length()
    rescue
      _ -> 0
    end
  end

  defp git_info(path) do
    case System.cmd("git", ["rev-parse", "--show-toplevel"], cd: path, stderr_to_stdout: true) do
      {_, 0} ->
        {branch, _} = System.cmd("git", ["branch", "--show-current"], cd: path, stderr_to_stdout: true)
        {remote, _} = System.cmd("git", ["remote", "get-url", "origin"], cd: path, stderr_to_stdout: true)

        %{
          is_repo: true,
          branch: String.trim(branch),
          remote: String.trim(remote)
        }

      _ ->
        %{is_repo: false}
    end
  end
end
