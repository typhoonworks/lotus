defmodule Lotus.AI.Actions.GetColumnValues do
  @moduledoc """
  Retrieves distinct values for a specific column.

  Useful for discovering enum values, status codes, categories, etc.
  Returns up to 100 unique values.
  """

  @behaviour Lotus.AI.Action

  alias Lotus.SQL.Identifier

  @impl true
  def name, do: "get_column_values"

  @impl true
  def description,
    do:
      "Get distinct values for a specific column in a table. " <>
        "Useful for discovering enum values, status codes, categories, etc. " <>
        "Returns up to 100 unique values."

  @impl true
  def schema do
    [
      data_source: [
        type: :string,
        required: true,
        doc: "Name of the data source to query"
      ],
      table_name: [
        type: :string,
        required: true,
        doc: "Schema-qualified table name (e.g., 'reporting.invoices')"
      ],
      column_name: [
        type: :string,
        required: true,
        doc: "Name of the column to get distinct values for"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    {schema, table} = Identifier.parse_table_name(params.table_name)

    with :ok <- Identifier.validate_table_parts(schema, table),
         :ok <- Identifier.validate_identifier(params.column_name, "column name") do
      execute_query(schema, table, params)
    end
  end

  defp execute_query(nil, table, params) do
    query =
      ~s(SELECT DISTINCT "#{params.column_name}" FROM "#{table}" WHERE "#{params.column_name}" IS NOT NULL ORDER BY "#{params.column_name}" LIMIT 100)

    run_and_format(query, params)
  end

  defp execute_query(schema, table, params) do
    query =
      ~s(SELECT DISTINCT "#{params.column_name}" FROM "#{schema}"."#{table}" WHERE "#{params.column_name}" IS NOT NULL ORDER BY "#{params.column_name}" LIMIT 100)

    run_and_format(query, params)
  end

  defp run_and_format(query, params) do
    case Lotus.run_statement(query, [], repo: params.data_source) do
      {:ok, result} ->
        values = Enum.map(result.rows, fn [value] -> Lotus.Normalizer.normalize(value) end)

        {:ok,
         %{
           table: params.table_name,
           column: params.column_name,
           values: values,
           count: length(values)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
