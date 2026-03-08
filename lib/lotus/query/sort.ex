defmodule Lotus.Query.Sort do
  @moduledoc """
  Represents a sort directive to apply on query results.

  Sorts are source-agnostic data structures that describe a column-level
  ordering. Each source adapter knows how to translate sorts into its
  native query language (e.g., SQL ORDER BY clauses).

  ## Examples

      %Sort{column: "created_at", direction: :desc}
      %Sort{column: "name", direction: :asc}
  """

  @type direction :: :asc | :desc

  @type t :: %__MODULE__{
          column: String.t(),
          direction: direction()
        }

  @enforce_keys [:column, :direction]
  defstruct [:column, :direction]

  @directions ~w(asc desc)a

  @doc """
  Creates a new sort, validating the direction.
  """
  @spec new(String.t(), direction()) :: t()
  def new(column, direction) when direction in @directions do
    %__MODULE__{column: column, direction: direction}
  end

  @doc """
  Returns the list of valid direction atoms.
  """
  @spec directions() :: [direction(), ...]
  def directions, do: @directions

  @doc """
  Returns a human-readable label for the given direction.
  """
  @spec direction_label(direction()) :: String.t()
  def direction_label(:asc), do: "ASC"
  def direction_label(:desc), do: "DESC"
end
