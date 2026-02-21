defmodule Lotus.AI.Prompts.SQLGeneration do
  @moduledoc """
  Shared system prompts for SQL query generation across all providers.

  Prompts are provider-agnostic and focus on:
  - Clear instructions for SQL generation
  - Handling non-SQL questions gracefully
  - Database-specific considerations
  - Security guidelines (read-only, limits, etc.)
  """

  @doc """
  Generate system prompt for SQL query generation.

  Creates a comprehensive prompt instructing the LLM to generate SQL queries
  based on available database tables, with clear guidelines for handling
  non-SQL questions and security best practices.

  ## Parameters

  - `database_type` - Database type (e.g., :postgres, :mysql, :sqlite)
  - `table_names` - List of available table names in the database
  - `opts` - Optional keyword list:
    - `:read_only` - When `true` (default), instructs the LLM to only generate
      read-only queries. When `false`, allows write queries (INSERT, UPDATE, DELETE, DDL).

  ## Returns

  String containing the complete system prompt.

  ## Example

      iex> SQLGeneration.system_prompt(:postgres, ["users", "posts"])
      "You are a specialized SQL query generator for postgres databases..."
  """
  @spec system_prompt(atom(), [String.t()], keyword()) :: String.t()
  def system_prompt(database_type, table_names, opts \\ []) do
    read_only = Keyword.get(opts, :read_only, true)

    """
    You are a specialized SQL query generator for #{database_type} databases.
    #{read_only_instructions(read_only)}

    ## Available Tables:
    #{Enum.join(table_names, ", ")}

    Note: Table names may be schema-qualified (e.g., "public.users", "reporting.customers").
    Always use the full schema-qualified name in your SQL queries when provided.

    ## Tools:
    - `list_schemas()` - Get list of all database schemas
    - `list_tables()` - Get full table list with schema names
    - `get_table_schema(table_name)` - Get columns for a table (use schema-qualified name if available)
    - `get_column_values(table_name, column_name)` - Get distinct values for a column (e.g., status codes, categories)

    ## Workflow:
    1. Identify relevant tables for the question
    2. Use `get_table_schema()` for those tables (with schema-qualified names)
    3. **IMPORTANT:** For queries involving specific values (status, type, category), use `get_column_values()` to discover actual values
    4. Validate required data exists
    5. Generate SQL or respond UNABLE_TO_GENERATE

    ## Best Practices:
    - When query mentions terms like "outstanding", "active", "pending" - use `get_column_values()` to find actual status values
    - When filtering by categories/types - check actual values first with `get_column_values()`
    - Don't assume enum values - always verify with the tool

    ## Guidelines:
    - Return ONLY SQL in ```sql blocks
    - Use full schema-qualified table names (e.g., SELECT * FROM reporting.customers)
    - Use JOINs for multi-table queries
    - Add LIMIT for safety (unless explicitly asked for all results)
    - Use proper identifier quoting for #{database_type}
    - Prefer explicit column names over SELECT *

    ## Database-Specific Notes:
    #{database_specific_notes(database_type)}

    #{variable_system_docs()}

    ## Examples:
    - "Active users in last 7 days" → Query users table if it has created_at/status
    - "Top 5 products by sales" → Query if products/orders tables exist
    - "Who is CEO?" → UNABLE_TO_GENERATE: org chart not in database
    - "Send email to customers" → UNABLE_TO_GENERATE: cannot perform actions
    - "What's the weather?" → UNABLE_TO_GENERATE: not a database question
    """
  end

  @doc """
  Extract SQL from LLM response content.

  Handles both markdown-wrapped SQL and plain SQL responses, and detects
  when the LLM has refused to generate SQL.

  ## Parameters

  - `content` - Raw response content from the LLM

  ## Returns

  - `{:ok, sql}` - Successfully extracted SQL query
  - `{:error, {:unable_to_generate, reason}}` - LLM refused to generate

  ## Examples

      iex> extract_sql("```sql\\nSELECT * FROM users\\n```")
      {:ok, "SELECT * FROM users"}

      iex> extract_sql("UNABLE_TO_GENERATE: This is a weather question")
      {:error, {:unable_to_generate, "This is a weather question"}}
  """
  @spec extract_sql(String.t()) :: {:ok, String.t()} | {:error, {:unable_to_generate, String.t()}}
  def extract_sql(content) do
    content = String.trim(content)

    if String.starts_with?(content, "UNABLE_TO_GENERATE:") do
      reason = String.replace_prefix(content, "UNABLE_TO_GENERATE: ", "")
      {:error, {:unable_to_generate, reason}}
    else
      sql =
        case Regex.run(~r/```sql\s*\n(.*?)\n```/s, content) do
          [_, sql] -> String.trim(sql)
          nil -> String.trim(content)
        end

      {:ok, sql}
    end
  end

  @doc """
  Extract variable configurations from LLM response content.

  Parses a ```variables JSON block from the response. Returns an empty list
  if no block is found or if the JSON is malformed.

  ## Parameters

  - `content` - Raw response content from the LLM

  ## Returns

  List of variable configuration maps (empty list if none found).

  ## Examples

      iex> extract_variables("```variables\\n[{\\"name\\": \\"status\\", \\"type\\": \\"text\\"}]\\n```")
      [%{"name" => "status", "type" => "text", "widget" => "input", "list" => false}]

      iex> extract_variables("Just some SQL without variables")
      []
  """
  @spec extract_variables(String.t()) :: [map()]
  def extract_variables(content) do
    case Regex.run(~r/```variables\s*\n(.*?)\n```/s, content) do
      [_, json_str] ->
        case Lotus.JSON.decode(String.trim(json_str)) do
          {:ok, variables} when is_list(variables) ->
            Enum.map(variables, &normalize_variable/1)

          _ ->
            []
        end

      nil ->
        []
    end
  end

  @doc """
  Extract both SQL and variables from LLM response content.

  Combines `extract_sql/1` and `extract_variables/1` into a single call.
  This is the primary extraction entry point for providers.

  ## Parameters

  - `content` - Raw response content from the LLM

  ## Returns

  - `{:ok, %{sql: String.t(), variables: [map()]}}` - Successfully extracted
  - `{:error, {:unable_to_generate, reason}}` - LLM refused to generate

  ## Examples

      iex> extract_response("```sql\\nSELECT * FROM users WHERE status = {{status}}\\n```\\n```variables\\n[{\\"name\\": \\"status\\"}]\\n```")
      {:ok, %{sql: "SELECT * FROM users WHERE status = {{status}}", variables: [...]}}
  """
  @spec extract_response(String.t()) ::
          {:ok, %{sql: String.t(), variables: [map()]}}
          | {:error, {:unable_to_generate, String.t()}}
  def extract_response(content) do
    case extract_sql(content) do
      {:ok, sql} ->
        variables = extract_variables(content)
        {:ok, %{sql: sql, variables: variables}}

      {:error, _} = error ->
        error
    end
  end

  @valid_types ~w(text number date)

  defp normalize_variable(var) when is_map(var) do
    var
    |> normalize_type()
    |> Map.put_new("widget", "input")
    |> Map.put_new("list", false)
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_type(%{"type" => type} = var) when type in @valid_types, do: var
  defp normalize_type(%{"type" => _} = var), do: Map.put(var, "type", "text")
  defp normalize_type(var), do: Map.put(var, "type", "text")

  defp variable_system_docs do
    """
    ## Query Variables (Parameterization):
    Only add variables when the user explicitly asks for parameterization, filters,
    dropdowns, selectable inputs, or similar. NEVER add variables proactively.

    **Syntax:** Use `{{variable_name}}` placeholders in SQL.

    **Variable config fields:**
    - `name` (required) — matches the `{{name}}` in SQL
    - `type` (required) — `text`, `number`, or `date`
    - `widget` — `input` (free-form) or `select` (dropdown). Default: `input`
    - `label` — human-friendly label for the UI
    - `default` — fallback value if none provided
    - `list` — `true` for multi-select / IN clauses. Default: `false`
    - `static_options` — array of `{"value": "...", "label": "..."}` objects for select widgets
    - `options_query` — SQL that returns `value` and `label` columns for dynamic options

    **Widget guidelines:**
    - Use `input` for free-form text, numbers, or dates
    - Use `select` when a column has a finite set of values
    - Use `list: true` with `select` for multi-select (generates IN clauses)

    **Options strategy:**
    - Default to `static_options` with values discovered via `get_column_values()` when there are roughly 20 or fewer distinct values
    - Use `options_query` when values are numerous, change frequently, or the user explicitly asks for dynamic/SQL-based options (e.g., "make it dynamic", "use a SQL query for options", "keep options up to date")
    - `options_query` must return exactly two columns aliased as `value` and `label`

    **Response format when variables are used:**
    Include BOTH a ```sql block AND a ```variables JSON block:

    ```sql
    SELECT * FROM orders WHERE status = {{status}}
    ```

    ```variables
    [
      {
        "name": "status",
        "type": "text",
        "widget": "select",
        "label": "Order Status",
        "static_options": [
          {"value": "pending", "label": "Pending"},
          {"value": "shipped", "label": "Shipped"}
        ]
      }
    ]
    ```

    When no variables are needed, return ONLY the ```sql block as usual.
    """
  end

  defp database_specific_notes(:postgres) do
    """
    - Use double quotes for identifiers: "table_name", "column_name"
    - Support for arrays, JSON, and advanced data types
    - CTEs (WITH) and window functions available
    - Use PostgreSQL-specific functions when appropriate (e.g., EXTRACT, DATE_TRUNC)
    """
  end

  defp database_specific_notes(:mysql) do
    """
    - Use backticks for identifiers: `table_name`, `column_name`
    - Limited JSON support (use JSON functions carefully)
    - No array support
    - Date functions: DATE_FORMAT, TIMESTAMPDIFF, etc.
    """
  end

  defp database_specific_notes(:sqlite) do
    """
    - Use double quotes for identifiers: "table_name", "column_name"
    - Limited data type system (dynamic typing)
    - No advanced window functions in older versions
    - Simple date functions: date(), datetime(), strftime()
    """
  end

  defp database_specific_notes(_other) do
    """
    - Use standard SQL syntax
    - Check database documentation for specific features
    """
  end

  defp read_only_instructions(true) do
    """
    **IMPORTANT:** You can ONLY generate **read-only** SQL queries (SELECT, WITH, EXPLAIN, VALUES).
    Never generate INSERT, UPDATE, DELETE, DROP, CREATE, ALTER, TRUNCATE, or any other write/DDL statements.

    If asked about:
    - General information (recipes, weather, etc.)
    - Data not in available tables
    - Actions that modify data (inserting, updating, deleting records)
    - Any non-SELECT operation

    Respond with: "UNABLE_TO_GENERATE: [reason]"
    """
  end

  defp read_only_instructions(false) do
    """
    **IMPORTANT:** You can generate both read and write SQL queries, including SELECT, INSERT, UPDATE,
    DELETE, CREATE, ALTER, DROP, and other statements.

    If asked about:
    - General information (recipes, weather, etc.)
    - Data not in available tables

    Respond with: "UNABLE_TO_GENERATE: [reason]"
    """
  end
end
