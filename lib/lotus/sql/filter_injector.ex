defmodule Lotus.SQL.FilterInjector do
  @moduledoc ~S"""
  Shared helpers for SQL-based sources to inject filter conditions into queries.

  Wraps the original query in a CTE and appends WHERE clauses. Each SQL source
  calls this with its own `quote_fn` for identifier quoting.

  ## Example

      quote_fn = fn id -> ~s("#{id}") end
      Lotus.SQL.FilterInjector.apply("SELECT * FROM users", [
        %Lotus.Query.Filter{column: "region", op: :eq, value: "US"}
      ], quote_fn)
      #=> ~s(WITH _base AS (SELECT * FROM users) SELECT * FROM _base WHERE "region" = 'US')
  """

  alias Lotus.Query.Filter

  @doc """
  Wraps the given SQL in a CTE and appends WHERE clauses for each filter.

  `quote_fn` is a 1-arity function that quotes an identifier for the target database.

  Returns the original SQL unchanged if filters is empty.
  """
  @spec apply(String.t(), [Filter.t()], (String.t() -> String.t())) :: String.t()
  def apply(sql, [], _quote_fn), do: sql

  def apply(sql, filters, quote_fn) when is_list(filters) and is_function(quote_fn, 1) do
    conditions = Enum.map_join(filters, " AND ", &build_condition(&1, quote_fn))
    "WITH _base AS (#{sql}) SELECT * FROM _base WHERE #{conditions}"
  end

  defp build_condition(%Filter{column: column, op: :is_null}, quote_fn) do
    "#{quote_fn.(column)} IS NULL"
  end

  defp build_condition(%Filter{column: column, op: :is_not_null}, quote_fn) do
    "#{quote_fn.(column)} IS NOT NULL"
  end

  defp build_condition(%Filter{column: column, op: op, value: value}, quote_fn) do
    "#{quote_fn.(column)} #{op_to_sql(op)} #{quote_value(value)}"
  end

  defp op_to_sql(:eq), do: "="
  defp op_to_sql(:neq), do: "!="
  defp op_to_sql(:gt), do: ">"
  defp op_to_sql(:lt), do: "<"
  defp op_to_sql(:gte), do: ">="
  defp op_to_sql(:lte), do: "<="
  defp op_to_sql(:like), do: "LIKE"

  @doc """
  Quotes a value as a SQL literal, handling type-appropriate formatting.
  """
  @spec quote_value(term()) :: String.t()
  def quote_value(nil), do: "NULL"
  def quote_value(value) when is_integer(value), do: Integer.to_string(value)
  def quote_value(value) when is_float(value), do: Float.to_string(value)
  def quote_value(true), do: "TRUE"
  def quote_value(false), do: "FALSE"

  def quote_value(%Decimal{} = value), do: Decimal.to_string(value)

  def quote_value(value) when is_binary(value) do
    escaped = String.replace(value, "'", "''")
    "'#{escaped}'"
  end

  def quote_value(value), do: quote_value(to_string(value))
end
