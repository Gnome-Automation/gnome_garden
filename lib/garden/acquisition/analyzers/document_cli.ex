defmodule GnomeGarden.Acquisition.Analyzers.DocumentCLI do
  @moduledoc """
  Lightweight AshStorage analyzer for procurement packet files.

  The analyzer is deliberately optional-tool friendly. If local CLI tools are
  missing, upload still succeeds and the blob metadata records what was skipped.
  """

  @behaviour AshStorage.Analyzer

  @max_text_chars 12_000

  @impl true
  def accept?("application/pdf"), do: true
  def accept?("text/plain"), do: true
  def accept?("text/" <> _), do: true
  def accept?("image/" <> _), do: true
  def accept?(_content_type), do: false

  @impl true
  def analyze(path, opts) do
    content_type =
      opts
      |> Keyword.get(:content_type)
      |> normalize_content_type(path)

    result =
      path
      |> extract(content_type)
      |> Map.put("analyzer", "document_cli")
      |> Map.put("content_type", content_type)
      |> Map.put(
        "analyzed_at",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    {:ok, %{"document_analysis" => result}}
  end

  defp extract(path, "application/pdf") do
    case find_tool("pdftotext") do
      nil ->
        unavailable("pdftotext")

      tool ->
        tool
        |> run([path, "-"])
        |> text_result("pdftotext")
    end
  end

  defp extract(path, "text/" <> _) do
    path
    |> File.read()
    |> case do
      {:ok, text} -> text_metadata(text, "file")
      {:error, reason} -> %{"status" => "failed", "reason" => inspect(reason), "tool" => "file"}
    end
  end

  defp extract(path, "image/" <> _) do
    ocr_result =
      case find_tool("tesseract") do
        nil -> unavailable("tesseract")
        tool -> tool |> run([path, "stdout"]) |> text_result("tesseract")
      end

    image_result =
      case find_tool("identify") do
        nil -> %{"image_tool" => "identify", "image_status" => "tool_unavailable"}
        tool -> image_metadata(tool, path)
      end

    Map.merge(ocr_result, image_result)
  end

  defp extract(_path, content_type) do
    %{
      "status" => "skipped",
      "reason" => "unsupported_content_type",
      "content_type" => content_type
    }
  end

  defp text_result({output, 0}, tool), do: text_metadata(output, tool)

  defp text_result({output, code}, tool) do
    %{
      "status" => "failed",
      "tool" => tool,
      "exit_code" => code,
      "reason" => String.slice(String.trim(output), 0, 500)
    }
  end

  defp text_metadata(text, tool) do
    text = normalize_text(text)

    %{
      "status" => if(text == "", do: "empty", else: "complete"),
      "tool" => tool,
      "text_excerpt" => String.slice(text, 0, @max_text_chars),
      "word_count" => word_count(text),
      "line_count" => text |> String.split("\n", trim: true) |> length(),
      "keyword_hits" => keyword_hits(text)
    }
    |> Map.merge(structured_analysis(text))
  end

  defp structured_analysis(""), do: %{}

  defp structured_analysis(text) do
    sentences = sentences(text)

    %{
      "scope_summary" => scope_summary(sentences, text),
      "due_date_mentions" => date_mentions(text),
      "submission_instructions" =>
        matching_sentences(sentences, [
          "submit",
          "submission",
          "proposal",
          "bid due",
          "sealed",
          "portal"
        ]),
      "mandatory_meeting" =>
        matching_sentences(sentences, ["mandatory", "pre-bid", "pre proposal", "site visit"]),
      "required_licenses_certs" =>
        matching_sentences(sentences, ["license", "certification", "certified", "cert"]),
      "bonding_insurance" => matching_sentences(sentences, ["bond", "insurance", "insured"]),
      "red_flags" => red_flags(sentences),
      "next_action" => next_action(text, sentences)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp image_metadata(tool, path) do
    case run(tool, ["-format", "%m %w %h", path]) do
      {output, 0} ->
        case String.split(String.trim(output), " ") do
          [format, width, height] ->
            %{
              "image_status" => "complete",
              "image_format" => format,
              "width" => width,
              "height" => height
            }

          _ ->
            %{"image_status" => "complete", "image_raw" => String.trim(output)}
        end

      {output, code} ->
        %{
          "image_status" => "failed",
          "image_exit_code" => code,
          "image_reason" => String.slice(output, 0, 500)
        }
    end
  end

  defp unavailable(tool), do: %{"status" => "tool_unavailable", "tool" => tool}

  defp find_tool(tool), do: System.find_executable(tool)

  defp run(tool, args), do: System.cmd(tool, args, stderr_to_stdout: true)

  defp normalize_content_type(nil, path), do: normalize_content_type(MIME.from_path(path), path)

  defp normalize_content_type("application/octet-stream", path) do
    case find_tool("file") do
      nil ->
        "application/octet-stream"

      tool ->
        case run(tool, ["--mime-type", "-b", path]) do
          {output, 0} -> String.trim(output)
          _ -> "application/octet-stream"
        end
    end
  end

  defp normalize_content_type(content_type, _path), do: content_type

  defp normalize_text(text) do
    text
    |> to_string()
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp word_count(""), do: 0

  defp word_count(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp keyword_hits(text) do
    text = String.downcase(text)

    [
      "scada",
      "plc",
      "controls",
      "automation",
      "instrumentation",
      "water",
      "wastewater",
      "pump",
      "telemetry",
      "hmi",
      "ignition"
    ]
    |> Enum.filter(&String.contains?(text, &1))
  end

  defp sentences(text) do
    text
    |> String.split(~r/(?<=[\.\!\?])\s+|\n+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp scope_summary(sentences, text) do
    sentences
    |> Enum.find(fn sentence ->
      contains_any?(sentence, ["scope", "work", "project", "services", "replace", "upgrade"])
    end)
    |> case do
      nil -> String.slice(text, 0, 260)
      sentence -> String.slice(sentence, 0, 260)
    end
  end

  defp date_mentions(text) do
    ~r/\b(?:\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4})\b/i
    |> Regex.scan(text)
    |> Enum.map(&List.first/1)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp matching_sentences(sentences, terms) do
    sentences
    |> Enum.filter(&contains_any?(&1, terms))
    |> Enum.map(&String.slice(&1, 0, 220))
    |> Enum.take(3)
  end

  defp red_flags(sentences) do
    matching_sentences(sentences, [
      "mandatory",
      "bond",
      "insurance",
      "prevailing wage",
      "liquidated damages",
      "sole source",
      "addendum"
    ])
  end

  defp next_action(text, sentences) do
    cond do
      contains_any?(text, ["mandatory", "pre-bid", "site visit"]) ->
        "Confirm mandatory meeting or site visit requirements before pursuing."

      date_mentions(text) != [] ->
        "Confirm deadline and submission instructions from the packet."

      matching_sentences(sentences, ["license", "certification", "bond", "insurance"]) != [] ->
        "Validate license, bonding, and insurance requirements before accepting."

      true ->
        "Review extracted scope and decide whether more evidence is needed."
    end
  end

  defp contains_any?(text, terms) do
    text = String.downcase(text)
    Enum.any?(terms, &String.contains?(text, &1))
  end
end
