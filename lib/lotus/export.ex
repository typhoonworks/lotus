defmodule Lotus.Export do
  @moduledoc """
  Export functionality for Lotus.Result to various formats.
  """

  alias Lotus.Config
  alias Lotus.Result
  alias Lotus.Storage.Query
  alias Lotus.Value

  @default_page_size 1000

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
  Runs a Query and converts the full, unpaginated result to CSV iodata.

  Accepts a `%Lotus.Storage.Query{}` and Lotus options such as `:repo`, `:vars`,
  and `:search_path`. Pagination is explicitly disabled (no window) to fetch all
  matching rows.

  Raises on execution errors.
  """
  @spec to_csv(Query.t(), keyword()) :: [binary() | iodata()]
  def to_csv(%Query{} = q, opts \\ []) do
    run_opts = Keyword.merge(opts, window: nil)

    case Lotus.run_query(q, run_opts) do
      {:ok, %Result{} = res} -> to_csv(res)
      {:error, err} -> raise ArgumentError, "to_csv/2 failed: #{inspect(err)}"
    end
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

  @doc """
  Stream a CSV export for a Query by fetching pages of results.

  Uses windowed pagination under the hood and outputs CSV iodata chunks. The
  first yielded chunk contains the header row. Subsequent chunks contain rows.

  Options:
  - `:page_size` — page size used for windowed fetching (defaults to configured
    Lotus default page size or 1000)
  - Any `Lotus.run_query/2` option such as `:repo`, `:vars`, `:search_path`.

  Raises on execution errors during streaming.
  """
  @spec stream_csv(Query.t(), keyword()) :: Enumerable.t()
  def stream_csv(%Query{} = q, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, Config.default_page_size() || @default_page_size)

    Stream.resource(
      fn -> %{offset: 0, header?: false} end,
      fn %{offset: off, header?: header?} = state ->
        run_opts = Keyword.merge(opts, window: [limit: page_size, offset: off, count: :none])

        Lotus.run_query(q, run_opts)
        |> handle_csv_query_result(state, off, header?)
      end,
      fn _ -> :ok end
    )
  end

  defp handle_csv_query_result({:ok, %Result{columns: _cols, rows: []}}, state, _off, _header?) do
    {:halt, state}
  end

  defp handle_csv_query_result({:ok, %Result{columns: cols, rows: rows}}, _state, off, header?) do
    header = if header?, do: [], else: [CSVParser.dump_to_iodata([cols])]

    body =
      rows
      |> Stream.map(&normalize_row_for_csv/1)
      |> Stream.map(&CSVParser.dump_to_iodata([&1]))
      |> Enum.to_list()

    next = %{offset: off + length(rows), header?: true}
    {header ++ body, next}
  end

  defp handle_csv_query_result({:error, err}, _state, _off, _header?) do
    raise "stream_csv(query) execution error: #{inspect(err)}"
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
