defmodule Lotus.AI.Actions.ListTables do
  @moduledoc """
  Lists all available tables in a database.

  Returns schema-qualified table names (e.g., "public.users", "reporting.customers")
  for databases with schemas, or plain table names for schema-less databases.
  """

  @behaviour Lotus.AI.Action

  @impl true
  def name, do: "list_tables"

  @impl true
  def description,
    do:
      "Get list of all available tables in the database with their schemas " <>
        "(e.g., 'public.users', 'reporting.customers')"

  @impl true
  def schema do
    [
      data_source: [type: :string, required: true, doc: "Name of the data source to query"]
    ]
  end

  @impl true
  def run(params, _context) do
    case Lotus.Schema.list_tables(params.data_source) do
      {:ok, tables} ->
        {:ok, %{tables: format_table_names(tables)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_table_names(tables) do
    Enum.map(tables, fn
      {schema, table} when not is_nil(schema) -> "#{schema}.#{table}"
      table -> table
    end)
  end
end
