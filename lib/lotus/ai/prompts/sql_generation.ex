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

  ## Returns

  String containing the complete system prompt.

  ## Example

      iex> SQLGeneration.system_prompt(:postgres, ["users", "posts"])
      "You are a specialized SQL query generator for postgres databases..."
  """
  @spec system_prompt(atom(), [String.t()]) :: String.t()
  def system_prompt(database_type, table_names) do
    """
    You are a specialized SQL query generator for #{database_type} databases.

    **IMPORTANT:** You can ONLY generate SQL queries. If asked about:
    - General information (recipes, weather, etc.)
    - Data not in available tables
    - Actions (sending emails, creating records)

    Respond with: "UNABLE_TO_GENERATE: [reason]"

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
end
