defmodule Lotus.AI.Tools.SchemaTools do
  @moduledoc """
  Shared tool implementations for schema introspection.

  These tools are provider-agnostic and can be adapted to any LLM provider's
  tool/function calling format. Each function returns JSON-encoded results.
  """

  @doc """
  Get list of all available schemas in the database.

  ## Parameters

  - `data_source` - Name of the data source to query

  ## Returns

  - `{:ok, json_string}` - JSON-encoded list of schema names
  - `{:error, reason}` - Error fetching schemas

  ## Example Response

      {:ok, ~s({"schemas": ["public", "reporting", "analytics"]})}
  """
  @spec list_schemas(String.t()) :: {:ok, String.t()} | {:error, term()}
  def list_schemas(data_source) do
    case Lotus.Schema.list_schemas(data_source) do
      {:ok, schemas} ->
        {:ok, Lotus.JSON.encode!(%{schemas: schemas})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get list of all available tables in the database.

  ## Parameters

  - `data_source` - Name of the data source to query

  ## Returns

  - `{:ok, json_string}` - JSON-encoded list of schema-qualified table names
  - `{:error, reason}` - Error fetching tables

  ## Example Response

      {:ok, ~s({"tables": ["public.users", "public.posts", "reporting.customers"]})}
  """
  @spec list_tables(String.t()) :: {:ok, String.t()} | {:error, term()}
  def list_tables(data_source) do
    case Lotus.Schema.list_tables(data_source) do
      {:ok, tables} ->
        table_names = format_table_names(tables)
        {:ok, Lotus.JSON.encode!(%{tables: table_names})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get column details for a specific table.

  ## Parameters

  - `data_source` - Name of the data source to query
  - `table_name` - Schema-qualified table name (e.g., "reporting.customers") or just table name

  ## Returns

  - `{:ok, json_string}` - JSON-encoded table schema with columns
  - `{:error, reason}` - Error fetching schema

  ## Example Response

      {:ok, ~s({
        "table": "reporting.customers",
        "columns": [
          {"name": "id", "type": "integer", "nullable": false, "primary_key": true},
          {"name": "email", "type": "varchar", "nullable": false, "primary_key": false}
        ]
      })}
  """
  @spec get_table_schema(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_table_schema(data_source, table_name) do
    # Parse schema-qualified table name if present
    {schema, table} = parse_table_name(data_source, table_name)

    # Call with explicit schema if available
    result =
      case schema do
        nil -> Lotus.Schema.get_table_schema(data_source, table)
        _schema -> Lotus.Schema.get_table_schema(data_source, table, schema: schema)
      end

    case result do
      {:ok, columns} ->
        column_info =
          Enum.map(columns, fn col ->
            %{
              name: col.name,
              type: col.type,
              nullable: Map.get(col, :nullable, true),
              primary_key: Map.get(col, :primary_key, false)
            }
          end)

        result = %{
          table: table_name,
          columns: column_info
        }

        {:ok, Lotus.JSON.encode!(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get distinct values for a specific column in a table.

  ## Parameters

  - `data_source` - Name of the data source to query
  - `table_name` - Schema-qualified table name (e.g., "reporting.invoices")
  - `column_name` - Name of the column to get values for

  ## Returns

  - `{:ok, json_string}` - JSON-encoded list of distinct values (limited to 100)
  - `{:error, reason}` - Error fetching values

  ## Example Response

      {:ok, ~s({"table": "reporting.invoices", "column": "status", "values": ["open", "paid", "overdue"]})}
  """
  @spec get_column_values(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def get_column_values(data_source, table_name, column_name) do
    # Parse schema-qualified table name if present
    {schema, table} = parse_table_name(data_source, table_name)

    # Build the query to get distinct values
    {repo, _repo_name} = Lotus.Sources.resolve!(data_source, nil)

    query =
      case schema do
        nil ->
          ~s(SELECT DISTINCT "#{column_name}" FROM "#{table}" WHERE "#{column_name}" IS NOT NULL ORDER BY "#{column_name}" LIMIT 100)

        schema ->
          ~s(SELECT DISTINCT "#{column_name}" FROM "#{schema}"."#{table}" WHERE "#{column_name}" IS NOT NULL ORDER BY "#{column_name}" LIMIT 100)
      end

    case repo.query(query) do
      {:ok, %{rows: rows}} ->
        values = Enum.map(rows, fn [value] -> value end)

        result = %{
          table: table_name,
          column: column_name,
          values: values,
          count: length(values)
        }

        {:ok, Lotus.JSON.encode!(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Tool metadata for `list_schemas` tool.

  Returns a map describing the tool's purpose and parameters in a
  provider-agnostic format. Providers adapt this to their specific schemas.

  ## Returns

  Map with:
  - `:name` - Tool identifier
  - `:description` - What the tool does
  - `:parameters` - Empty map (no parameters required)
  """
  @spec list_schemas_metadata() :: map()
  def list_schemas_metadata do
    %{
      name: "list_schemas",
      description:
        "Get list of all available schemas in the database (e.g., 'public', 'reporting')",
      parameters: %{}
    }
  end

  @doc """
  Tool metadata for `list_tables` tool.

  Returns a map describing the tool's purpose and parameters in a
  provider-agnostic format. Providers adapt this to their specific schemas.

  ## Returns

  Map with:
  - `:name` - Tool identifier
  - `:description` - What the tool does
  - `:parameters` - Empty map (no parameters required)
  """
  @spec list_tables_metadata() :: map()
  def list_tables_metadata do
    %{
      name: "list_tables",
      description:
        "Get list of all available tables in the database with their schemas (e.g., 'public.users', 'reporting.customers')",
      parameters: %{}
    }
  end

  @doc """
  Tool metadata for `get_table_schema` tool.

  Returns a map describing the tool's purpose and parameters in a
  provider-agnostic format. Providers adapt this to their specific schemas.

  ## Returns

  Map with:
  - `:name` - Tool identifier
  - `:description` - What the tool does
  - `:parameters` - Map describing table_name parameter
  """
  @spec get_table_schema_metadata() :: map()
  def get_table_schema_metadata do
    %{
      name: "get_table_schema",
      description:
        "Get column details for a specific table including names, types, and constraints. Use schema-qualified names (e.g., 'reporting.customers') when tables exist in multiple schemas.",
      parameters: %{
        table_name: %{
          type: "string",
          description:
            "Schema-qualified table name (e.g., 'reporting.customers') or just table name",
          required: true
        }
      }
    }
  end

  @doc """
  Tool metadata for `get_column_values` tool.

  Returns a map describing the tool's purpose and parameters in a
  provider-agnostic format. Providers adapt this to their specific schemas.

  ## Returns

  Map with:
  - `:name` - Tool identifier
  - `:description` - What the tool does
  - `:parameters` - Map describing parameters
  """
  @spec get_column_values_metadata() :: map()
  def get_column_values_metadata do
    %{
      name: "get_column_values",
      description:
        "Get distinct values for a specific column in a table. Useful for discovering enum values, status codes, categories, etc. Returns up to 100 unique values.",
      parameters: %{
        table_name: %{
          type: "string",
          description: "Schema-qualified table name (e.g., 'reporting.invoices')",
          required: true
        },
        column_name: %{
          type: "string",
          description: "Name of the column to get distinct values for",
          required: true
        }
      }
    }
  end

  defp format_table_names(tables) do
    Enum.map(tables, fn
      {schema, table} when not is_nil(schema) -> "#{schema}.#{table}"
      table -> table
    end)
  end

  defp parse_table_name(_data_source, table_name) do
    case String.split(table_name, ".", parts: 2) do
      [schema, table] -> {schema, table}
      [table] -> {nil, table}
    end
  end
end
