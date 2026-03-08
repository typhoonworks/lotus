defmodule Lotus.AI.Actions.GetTableSchema do
  @moduledoc """
  Retrieves column details for a specific table.

  Returns column names, types, nullability, and primary key info.
  Accepts schema-qualified names (e.g., "reporting.customers").
  """

  @behaviour Lotus.AI.Action

  alias Lotus.SQL.Identifier

  @impl true
  def name, do: "get_table_schema"

  @impl true
  def description,
    do:
      "Get column details for a specific table including names, types, and constraints. " <>
        "Use schema-qualified names (e.g., 'reporting.customers') when tables exist in multiple schemas."

  @impl true
  def schema do
    [
      data_source: [type: :string, required: true, doc: "Name of the data source to query"],
      table_name: [
        type: :string,
        required: true,
        doc: "Schema-qualified table name (e.g., 'reporting.customers') or just table name"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    {schema, table} = Identifier.parse_table_name(params.table_name)

    with :ok <- Identifier.validate_table_parts(schema, table) do
      fetch_schema(params.data_source, schema, table, params.table_name)
    end
  end

  defp fetch_schema(data_source, nil, table, original_name) do
    format_result(Lotus.Schema.get_table_schema(data_source, table), original_name)
  end

  defp fetch_schema(data_source, schema, table, original_name) do
    format_result(
      Lotus.Schema.get_table_schema(data_source, table, schema: schema),
      original_name
    )
  end

  defp format_result({:ok, columns}, table_name) do
    column_info =
      Enum.map(columns, fn col ->
        %{
          name: col.name,
          type: col.type,
          nullable: Map.get(col, :nullable, true),
          primary_key: Map.get(col, :primary_key, false)
        }
      end)

    {:ok, %{table: table_name, columns: column_info}}
  end

  defp format_result({:error, reason}, _table_name), do: {:error, reason}
end
