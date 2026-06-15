defmodule GnomeGarden.Imports.Csv do
  @moduledoc """
  Small CSV reader for operator import files.

  This handles comma-separated files with quoted fields and escaped quotes. It is
  intentionally narrow: imports should pass parsed row maps into Ash actions,
  not put business behavior in CSV parsing code.
  """

  @spec read!(Path.t()) :: [map()]
  def read!(path) do
    path
    |> File.read!()
    |> parse!()
  end

  @spec parse!(String.t()) :: [map()]
  def parse!(contents) when is_binary(contents) do
    contents
    |> String.replace_prefix("\uFEFF", "")
    |> String.split(~r/\r\n|\n|\r/, trim: true)
    |> case do
      [] ->
        []

      [header | lines] ->
        headers = parse_line!(header)

        Enum.map(lines, fn line ->
          values = parse_line!(line)

          if length(values) != length(headers) do
            raise ArgumentError,
                  "CSV row has #{length(values)} fields, expected #{length(headers)}: #{line}"
          end

          headers
          |> Enum.zip(values)
          |> Map.new()
        end)
    end
  end

  defp parse_line!(line) do
    do_parse_line(line, "", [], false)
  end

  defp do_parse_line("", _field, _fields, true) do
    raise ArgumentError, "CSV line has an unterminated quoted field"
  end

  defp do_parse_line("", field, fields, false), do: Enum.reverse([field | fields])

  defp do_parse_line(<<"\"\"", rest::binary>>, field, fields, true) do
    do_parse_line(rest, field <> "\"", fields, true)
  end

  defp do_parse_line(<<"\"", rest::binary>>, field, fields, true) do
    do_parse_line(rest, field, fields, false)
  end

  defp do_parse_line(<<",", rest::binary>>, field, fields, false) do
    do_parse_line(rest, "", [field | fields], false)
  end

  defp do_parse_line(<<"\"", rest::binary>>, "", fields, false) do
    do_parse_line(rest, "", fields, true)
  end

  defp do_parse_line(<<char::utf8, rest::binary>>, field, fields, in_quote?) do
    do_parse_line(rest, field <> <<char::utf8>>, fields, in_quote?)
  end
end
