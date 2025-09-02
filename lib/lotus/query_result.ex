defmodule Lotus.QueryResult do
  @moduledoc """
  Represents the result of a SQL query execution.

  Contains the columns, rows, and metadata about the query result.
  """

  @enforce_keys [:columns, :rows]

  defstruct columns: [],
            rows: [],
            num_rows: nil,
            duration_ms: nil,
            command: nil,
            meta: %{}

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[term()]],
          num_rows: non_neg_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          command: String.t() | nil,
          meta: map()
        }

  @doc """
  Creates a new QueryResult from columns and rows.

  ## Examples

      iex> Lotus.QueryResult.new(["name", "age"], [["John", 25], ["Jane", 30]])
      %Lotus.QueryResult{
        columns: ["name", "age"],
        rows: [["John", 25], ["Jane", 30]],
        num_rows: 2,
        duration_ms: nil,
        command: nil,
        meta: %{}
      }
  """
  def new(columns, rows, opts \\ []) do
    %__MODULE__{
      columns: columns || [],
      rows: rows || [],
      num_rows: Keyword.get(opts, :num_rows, length(rows || [])),
      duration_ms: Keyword.get(opts, :duration_ms),
      command: Keyword.get(opts, :command),
      meta: Keyword.get(opts, :meta, %{})
    }
  end
end