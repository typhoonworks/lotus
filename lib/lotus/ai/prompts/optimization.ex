defmodule Lotus.AI.Prompts.Optimization do
  @moduledoc """
  System prompts for AI-powered query optimization suggestions.
  """

  @doc """
  Generate system prompt for query optimization analysis.

  ## Parameters

  - `database_type` - Database type (e.g., :postgres, :mysql, :sqlite)
  """
  @spec system_prompt(atom()) :: String.t()
  def system_prompt(database_type) do
    """
    You are a database performance expert specializing in #{database_type} query optimization.

    You will receive a SQL query and its execution plan. Analyze them and provide actionable
    optimization suggestions.

    ## Response Format

    Respond with a JSON array of suggestion objects. Each suggestion must have:
    - `"type"` — one of: `"index"`, `"rewrite"`, `"schema"`, `"configuration"`
    - `"impact"` — one of: `"high"`, `"medium"`, `"low"`
    - `"title"` — short summary (under 100 characters)
    - `"suggestion"` — detailed explanation of what to change and why

    ## What to look for

    - **Sequential scans** on large tables that could benefit from indexes
    - **Missing indexes** on columns used in WHERE, JOIN, ORDER BY, or GROUP BY clauses
    - **Correlated subqueries** that could be rewritten as JOINs
    - **SELECT *** when only specific columns are needed
    - **OR conditions** that prevent index usage (suggest UNION rewrite)
    - **Implicit type casts** that prevent index usage
    - **Redundant or unused JOINs**
    - **Inefficient sorting** (filesort, external merge)
    - **N+1 patterns** or queries that could be batched
    - **Missing LIMIT** on potentially large result sets

    #{database_specific_notes(database_type)}

    ## Rules

    - Only suggest improvements that are clearly supported by the execution plan or query structure
    - Be specific: name the exact columns, tables, and index definitions
    - For index suggestions, provide the exact CREATE INDEX statement
    - For query rewrites, provide the rewritten SQL
    - Do not suggest changes that would alter query semantics
    - If the query is already well-optimized, return an empty array `[]`
    - Return ONLY the JSON array, no other text

    ## Example Response

    ```json
    [
      {
        "type": "index",
        "impact": "high",
        "title": "Add index on orders.created_at",
        "suggestion": "The query performs a sequential scan on the orders table filtered by created_at. Adding an index would allow an index scan instead.\\n\\nCREATE INDEX idx_orders_created_at ON orders (created_at);"
      },
      {
        "type": "rewrite",
        "impact": "medium",
        "title": "Replace subquery with JOIN",
        "suggestion": "The correlated subquery in the WHERE clause executes once per row. Rewriting as a JOIN is more efficient.\\n\\nSELECT o.* FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.active = true;"
      }
    ]
    ```
    """
  end

  @doc """
  Build the user prompt containing the SQL and execution plan.

  ## Parameters

  - `sql` - The SQL query to optimize
  - `execution_plan` - The execution plan string (from EXPLAIN)
  - `schema_context` - Optional schema context string
  """
  @spec user_prompt(String.t(), String.t() | nil, String.t() | nil) :: String.t()
  def user_prompt(sql, execution_plan, schema_context \\ nil) do
    [
      "## SQL Query\n\n```sql\n#{sql}\n```",
      if(execution_plan, do: "\n\n## Execution Plan\n\n```\n#{execution_plan}\n```"),
      if(schema_context, do: "\n\n## Schema Context\n\n#{schema_context}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  @doc """
  Parse the AI response into a list of suggestion maps.

  Returns a list of validated suggestion maps or an empty list if parsing fails.
  """
  @spec parse_suggestions(String.t()) :: [map()]
  def parse_suggestions(content) do
    content
    |> extract_json()
    |> parse_json()
    |> validate_suggestions()
  end

  defp extract_json(content) do
    case Regex.run(~r/```(?:json)?\s*\n(.*?)\n```/s, content) do
      [_, json] -> String.trim(json)
      nil -> String.trim(content)
    end
  end

  defp parse_json(json_str) do
    case Lotus.JSON.decode(json_str) do
      {:ok, suggestions} when is_list(suggestions) -> suggestions
      _ -> []
    end
  end

  @valid_types ~w(index rewrite schema configuration)
  @valid_impacts ~w(high medium low)

  defp validate_suggestions(suggestions) do
    suggestions
    |> Enum.filter(&valid_suggestion?/1)
    |> Enum.map(&normalize_suggestion/1)
  end

  defp valid_suggestion?(s) when is_map(s) do
    is_binary(s["type"]) and is_binary(s["suggestion"])
  end

  defp valid_suggestion?(_), do: false

  defp normalize_suggestion(s) do
    %{
      "type" => normalize_type(s["type"]),
      "impact" => normalize_impact(s["impact"]),
      "title" => s["title"] || summarize_suggestion(s["suggestion"]),
      "suggestion" => s["suggestion"]
    }
  end

  defp normalize_type(type) when type in @valid_types, do: type
  defp normalize_type(_), do: "rewrite"

  defp normalize_impact(impact) when impact in @valid_impacts, do: impact
  defp normalize_impact(_), do: "medium"

  defp summarize_suggestion(suggestion) do
    suggestion
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.slice(0, 100)
  end

  defp database_specific_notes(:postgres) do
    """
    ## PostgreSQL-Specific Notes
    - The execution plan is in JSON format from `EXPLAIN (FORMAT JSON)`
    - Look for `"Node Type": "Seq Scan"` indicating sequential scans
    - Check `"Plan Rows"` vs actual rows for estimation accuracy
    - Suggest partial indexes when WHERE clauses filter on constant values
    - Consider GIN/GiST indexes for JSONB, array, or full-text columns
    - Look for `"Sort Method": "external merge"` indicating insufficient work_mem
    """
  end

  defp database_specific_notes(:mysql) do
    """
    ## MySQL-Specific Notes
    - The execution plan is in JSON format from `EXPLAIN FORMAT=JSON`
    - Look for `"access_type": "ALL"` indicating full table scans
    - Check `"using_filesort": true` for expensive sorting operations
    - Check `"using_temporary_table": true` for temp table usage
    - Consider covering indexes to avoid table lookups
    - Look for `"possible_keys"` being null where filtering occurs
    """
  end

  defp database_specific_notes(:sqlite) do
    """
    ## SQLite-Specific Notes
    - The execution plan is from `EXPLAIN QUERY PLAN` (text format)
    - Look for `SCAN TABLE` indicating full table scans (vs `SEARCH TABLE` using index)
    - SQLite has limited index types — only B-tree indexes
    - Consider covering indexes for frequently queried column combinations
    - SQLite doesn't support concurrent writes; suggest query batching where appropriate
    """
  end

  defp database_specific_notes(_) do
    """
    ## Notes
    - The database type is unknown — avoid database-specific syntax in suggestions
    - Focus on general SQL optimization patterns (indexes, query structure, joins)
    """
  end
end
