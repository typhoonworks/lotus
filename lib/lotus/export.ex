defmodule Lotus.Export do
  @moduledoc """
  Export functionality for Lotus.QueryResult to various formats.
  """

  alias Lotus.QueryResult
  alias Lotus.Export.Value

  @doc """
  Converts a QueryResult struct to CSV format using NimbleCSV.
  Returns iodata for efficient streaming.
  """
  NimbleCSV.define(CSVParser, separator: ",", escape: "\"")

  @spec to_csv(QueryResult.t()) :: iodata()
  def to_csv(%QueryResult{columns: columns, rows: rows}) do
    header = CSVParser.dump_to_iodata([columns])

    body =
      rows
      |> Stream.map(&normalize_row_for_csv/1)
      |> Stream.map(&CSVParser.dump_to_iodata([&1]))
      |> Enum.to_list()

    [header | body]
  end

  @doc """
  Converts a QueryResult struct to JSON format.
  Returns a binary string containing a JSON array of objects.
  """
  @spec to_json(QueryResult.t()) :: binary()
  def to_json(%QueryResult{columns: columns, rows: rows}) do
    rows
    |> Stream.map(&row_to_map_for_json(columns, &1))
    |> Enum.to_list()
    |> Lotus.JSON.encode!()
  end

  @doc """
  Converts a QueryResult struct to JSONL (JSON Lines) format.
  Returns a binary string with one JSON object per line.
  """
  @spec to_jsonl(QueryResult.t()) :: binary()
  def to_jsonl(%QueryResult{columns: columns, rows: rows}) do
    rows
    |> Stream.map(&row_to_map_for_json(columns, &1))
    |> Stream.map(&Lotus.JSON.encode!/1)
    |> Stream.intersperse("\n")
    |> Enum.join()
  end

  defp row_to_map_for_json(columns, row) do
    columns
    |> Enum.zip(row)
    |> Enum.map(fn {col, val} -> {col, Value.for_json(val)} end)
    |> Map.new()
  end

  defp normalize_row_for_csv(row) do
    Enum.map(row, &Value.to_csv_string/1)
  end
end
