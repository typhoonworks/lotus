defmodule Lotus.Query.Filter do
  @moduledoc """
  Represents a filter condition to apply on query results.

  Filters are source-agnostic data structures that describe a column-level
  predicate. Each source adapter knows how to translate filters into its
  native query language (e.g., SQL WHERE clauses via CTE wrapping).

  ## Examples

      %Filter{column: "region", op: :eq, value: "US"}
      %Filter{column: "price", op: :gt, value: 100}
      %Filter{column: "deleted_at", op: :is_null}
  """

  @type operator ::
          :eq | :neq | :gt | :lt | :gte | :lte | :like | :is_null | :is_not_null

  @type t :: %__MODULE__{
          column: String.t(),
          op: operator(),
          value: term()
        }

  @enforce_keys [:column, :op]
  defstruct [:column, :op, :value]

  @operators ~w(eq neq gt lt gte lte like is_null is_not_null)a

  @doc """
  Creates a new filter, validating the operator.
  """
  @spec new(String.t(), operator(), term()) :: t()
  def new(column, op, value \\ nil) when op in @operators do
    %__MODULE__{column: column, op: op, value: value}
  end

  @doc """
  Returns the list of valid operator atoms.
  """
  @spec operators() :: [operator(), ...]
  def operators, do: @operators

  @doc """
  Returns a human-readable label for the given operator.
  """
  @spec operator_label(operator()) :: String.t()
  def operator_label(:eq), do: "="
  def operator_label(:neq), do: "≠"
  def operator_label(:gt), do: ">"
  def operator_label(:lt), do: "<"
  def operator_label(:gte), do: "≥"
  def operator_label(:lte), do: "≤"
  def operator_label(:like), do: "LIKE"
  def operator_label(:is_null), do: "IS NULL"
  def operator_label(:is_not_null), do: "IS NOT NULL"
end
