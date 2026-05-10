defmodule GnomeGarden.Acquisition.Workers.RetryFailedImports do
  @moduledoc """
  Replays sidecar dead-letter entries through the pi RPC dispatcher.

  When the sidecar can't reach Phoenix or hits a transient failure, it appends
  the failed payload to `sidecar/_failed_imports.jsonl`. This cron worker
  reads the file, retries each entry, and rewrites the file with only the
  entries that still failed (incrementing `attempts` on each).

  Lines that succeed are appended to `sidecar/_retried.jsonl` for audit so
  no record is lost.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias GnomeGarden.Acquisition.PiRpcDispatcher
  alias GnomeGarden.Acquisition.PiRpcErrors

  @max_attempts 10

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    summary = retry()

    if summary.processed > 0 do
      Logger.info(
        "Pi failed-import retry: processed=#{summary.processed} " <>
          "succeeded=#{summary.succeeded} still_failing=#{summary.still_failing} " <>
          "abandoned=#{summary.abandoned}"
      )
    end

    :ok
  end

  @doc "Public entry point — runs a retry pass and returns a summary map."
  @spec retry() :: %{
          processed: non_neg_integer(),
          succeeded: non_neg_integer(),
          still_failing: non_neg_integer(),
          abandoned: non_neg_integer()
        }
  def retry do
    failed_path = failed_path()

    case File.read(failed_path) do
      {:ok, ""} ->
        empty_summary()

      {:ok, contents} ->
        process_contents(contents, failed_path)

      {:error, :enoent} ->
        empty_summary()

      {:error, reason} ->
        Logger.warning("Could not read #{failed_path}: #{inspect(reason)}")
        empty_summary()
    end
  end

  defp process_contents(contents, failed_path) do
    entries =
      contents
      |> String.split("\n", trim: true)
      |> Enum.map(&decode_line/1)

    {to_keep_acc, summary} =
      Enum.reduce(entries, {[], empty_summary()}, fn
        {:ok, entry}, {keep, sum} ->
          process_entry(entry, keep, %{sum | processed: sum.processed + 1})

        {:error, _raw}, {keep, sum} ->
          # Garbled line — drop it but count it as abandoned so it doesn't
          # silently disappear from the books.
          {keep, %{sum | abandoned: sum.abandoned + 1}}
      end)

    rewrite_failed_file(failed_path, Enum.reverse(to_keep_acc))
    summary
  end

  defp process_entry(entry, keep, summary) do
    action = Map.get(entry, "action")
    input = Map.get(entry, "input") || %{}
    attempts = Map.get(entry, "attempts", 0)

    case PiRpcDispatcher.dispatch(action, input) do
      {:ok, record} ->
        archive(action, input, record)
        {keep, %{summary | succeeded: summary.succeeded + 1}}

      {:error, reason} ->
        next_attempts = attempts + 1
        errors = PiRpcErrors.format(reason)

        updated =
          entry
          |> Map.put("attempts", next_attempts)
          |> Map.put("last_errors", errors)
          |> Map.put("last_attempt_at", DateTime.utc_now() |> DateTime.to_iso8601())

        if next_attempts >= @max_attempts do
          archive_abandoned(updated)
          {keep, %{summary | abandoned: summary.abandoned + 1}}
        else
          {[updated | keep], %{summary | still_failing: summary.still_failing + 1}}
        end
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, line}
    end
  end

  defp rewrite_failed_file(path, []) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> Logger.warning("Could not clear #{path}: #{inspect(reason)}")
    end
  end

  defp rewrite_failed_file(path, entries) do
    body =
      entries
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    File.write!(path, body)
  end

  defp archive(action, input, record) do
    line =
      Jason.encode!(%{
        action: action,
        input: input,
        result_id: record.id,
        retried_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    File.write!(retried_path(), line <> "\n", [:append])
  end

  defp archive_abandoned(entry) do
    line =
      Jason.encode!(Map.put(entry, "abandoned_at", DateTime.utc_now() |> DateTime.to_iso8601()))

    File.write!(abandoned_path(), line <> "\n", [:append])
  end

  defp empty_summary,
    do: %{processed: 0, succeeded: 0, still_failing: 0, abandoned: 0}

  defp failed_path, do: Path.join(sidecar_dir(), "_failed_imports.jsonl")
  defp retried_path, do: Path.join(sidecar_dir(), "_retried.jsonl")
  defp abandoned_path, do: Path.join(sidecar_dir(), "_abandoned.jsonl")

  defp sidecar_dir do
    Application.get_env(:gnome_garden, :sidecar_dir) ||
      Path.join(File.cwd!(), "sidecar")
  end
end
