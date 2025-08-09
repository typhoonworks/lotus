defmodule Lotus.QueryResult do
  @moduledoc """
  Represents the result of a SQL query execution.

  Contains the columns, rows, and metadata about the query result.
  """

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[any()]],
          num_rows: non_neg_integer()
        }

  defstruct [:columns, :rows, :num_rows]

  @doc """
  Creates a new QueryResult from columns and rows.

  ## Examples

      iex> Lotus.QueryResult.new(["name", "age"], [["John", 25], ["Jane", 30]])
      %Lotus.QueryResult{
        columns: ["name", "age"],
        rows: [["John", 25], ["Jane", 30]],
        num_rows: 2
      }
  """
  @spec new([String.t()], [[any()]]) :: t()
  def new(columns, rows) do
    %__MODULE__{
      columns: columns || [],
      rows: rows || [],
      num_rows: length(rows || [])
    }
  end
end
