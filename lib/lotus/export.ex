defmodule Lotus.Export do
  @moduledoc """
  Export functionality for Lotus.Result to various formats.
  """

  alias Lotus.Result
  alias Lotus.Value

  @doc """
  Converts a Result struct to CSV format using NimbleCSV.
  Returns iodata for efficient streaming.
  """
  NimbleCSV.define(CSVParser, separator: ",", escape: "\"")

  @spec to_csv(Result.t()) :: [binary() | iodata()]
  def to_csv(%Result{columns: columns, rows: rows}) do
    header = CSVParser.dump_to_iodata([columns])

    body =
      rows
      |> Stream.map(&normalize_row_for_csv/1)
      |> Stream.map(&CSVParser.dump_to_iodata([&1]))
      |> Enum.to_list()

    [header | body]
  end

  @doc """
  Converts a Result struct to JSON format.
  Returns a binary string containing a JSON array of objects.
  """
  @spec to_json(Result.t()) :: binary()
  def to_json(%Result{columns: columns, rows: rows}) do
    rows
    |> Stream.map(&row_to_map_for_json(columns, &1))
    |> Enum.to_list()
    |> Lotus.JSON.encode!()
  end

  @doc """
  Converts a Result struct to JSONL (JSON Lines) format.
  Returns a binary string with one JSON object per line.
  """
  @spec to_jsonl(Result.t()) :: binary()
  def to_jsonl(%Result{columns: columns, rows: rows}) do
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
