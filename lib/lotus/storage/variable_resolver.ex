defmodule Lotus.Storage.VariableResolver do
  @moduledoc """
  Extracts variable-to-column bindings from SQL queries.

  Parses SQL queries to determine which table.column each `{{variable}}` binds to.
  Uses regex-based heuristics (not full SQL parsing) for simplicity and performance.
  Handles 95% of common query patterns.

  ## Supported Patterns

  1. **Explicit**: `WHERE users.id = {{user_id}}`
  2. **Implicit**: `WHERE id = {{user_id}}` (resolves table from FROM clause)
  3. **Multiple vars**: `WHERE users.id = {{id}} AND users.email = {{email}}`
  4. **Aliased tables**: `WHERE u.id = {{id}}` (resolves alias 'u' to 'users')

  ## Limitations

  - Does not handle subqueries or complex JOINs perfectly
  - Assumes first table in FROM clause for implicit bindings
  - Best-effort heuristics, not a full SQL parser

  ## Usage

      sql = "SELECT * FROM users WHERE users.id = {{user_id}}"
      VariableResolver.resolve_variables(sql)
      # => [%{variable: "user_id", table: "users", column: "id"}]
  """

  @type variable_binding :: %{
          variable: String.t(),
          table: String.t() | nil,
          column: String.t()
        }

  @doc """
  Extract variable bindings from SQL statement.

  Returns list of bindings for each variable found in the query.

  ## Examples

      # Explicit binding
      resolve_variables("SELECT * FROM users WHERE users.id = {{user_id}}")
      # => [%{variable: "user_id", table: "users", column: "id"}]

      # Implicit binding
      resolve_variables("SELECT * FROM users WHERE id = {{user_id}}")
      # => [%{variable: "user_id", table: "users", column: "id"}]

      # With alias
      resolve_variables("SELECT * FROM users u WHERE u.id = {{user_id}}")
      # => [%{variable: "user_id", table: "users", column: "id"}]
  """
  @spec resolve_variables(sql :: String.t()) :: [variable_binding()]
  def resolve_variables(sql) when is_binary(sql) do
    sql_normalized = normalize_sql(sql)

    # Extract table aliases from FROM/JOIN clauses
    table_aliases = extract_table_aliases(sql_normalized)

    explicit_bindings = find_explicit_bindings(sql_normalized, table_aliases)
    implicit_bindings = find_implicit_bindings(sql_normalized, table_aliases)

    bound_vars =
      (explicit_bindings ++ implicit_bindings)
      |> Enum.map(& &1.variable)

    # Find unbound variables (e.g., in SELECT, VALUES, etc.)
    unbound_bindings = find_unbound_variables(sql_normalized, bound_vars)

    # Combine and deduplicate by variable name (explicit takes precedence)
    (explicit_bindings ++ implicit_bindings ++ unbound_bindings)
    |> Enum.uniq_by(& &1.variable)
  end

  # Normalize SQL: lowercase, remove comments, collapse whitespace
  defp normalize_sql(sql) do
    sql
    |> String.downcase()
    |> remove_comments()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp remove_comments(sql) do
    sql
    |> String.replace(~r/--.*?(\n|$)/, " ")
    |> String.replace(~r/\/\*.*?\*\//s, " ")
  end

  # Extract table aliases from FROM/JOIN clauses
  # Examples:
  #   FROM users u        -> {"u" => "users"}
  #   FROM users AS u     -> {"u" => "users"}
  #   JOIN orders o       -> {"o" => "orders"}
  defp extract_table_aliases(sql) do
    # Regex: FROM/JOIN table_name [AS] alias
    # Matches: table_name followed by optional AS and then an alias
    from_pattern = ~r/from\s+(\w+)(?:\s+as)?\s+(\w+)/
    join_pattern = ~r/join\s+(\w+)(?:\s+as)?\s+(\w+)/

    from_aliases =
      Regex.scan(from_pattern, sql)
      |> Enum.map(fn [_, table, alias] -> {alias, table} end)

    join_aliases =
      Regex.scan(join_pattern, sql)
      |> Enum.map(fn [_, table, alias] -> {alias, table} end)

    Map.new(from_aliases ++ join_aliases)
  end

  # Comparison operators to match in SQL
  @comparison_ops "=|<>|!=|<=|>=|<|>|like|ilike|in"

  # Find explicit bindings: table.column <op> {{variable}}
  # Also handles aliases: alias.column <op> {{variable}}
  defp find_explicit_bindings(sql, table_aliases) do
    # Regex: word.word <comparison_op> {{word}}
    # Matches: table_or_alias.column = {{variable}}
    pattern = ~r/(\w+)\.(\w+)\s*(?:#{@comparison_ops})\s*\{\{(\w+)\}\}/i

    Regex.scan(pattern, sql)
    |> Enum.map(fn [_, table_or_alias, column, variable] ->
      # Resolve alias to actual table name
      table = Map.get(table_aliases, table_or_alias, table_or_alias)

      %{
        variable: variable,
        table: table,
        column: column
      }
    end)
  end

  # Find implicit bindings: column <op> {{variable}}
  # Need to infer table from FROM clause
  defp find_implicit_bindings(sql, _table_aliases) do
    # Regex: column <op> {{var}} but NOT table.column <op> {{var}}
    # Negative lookbehind (?<!\.) ensures no dot before column name
    pattern = ~r/(?<!\.)\b(\w+)\s*(?:#{@comparison_ops})\s*\{\{(\w+)\}\}/i

    # Guess primary table from FROM clause (first table mentioned)
    primary_table = guess_primary_table(sql)

    Regex.scan(pattern, sql)
    |> Enum.map(fn [_, column, variable] ->
      %{
        variable: variable,
        table: primary_table,
        column: column
      }
    end)
  end

  # Find unbound variables: {{variable}} not matched by explicit or implicit patterns
  # These have no column binding (e.g., in SELECT list, VALUES clause, etc.)
  defp find_unbound_variables(sql, bound_variables) do
    # Find all {{variable}} patterns
    pattern = ~r/\{\{(\w+)\}\}/

    primary_table = guess_primary_table(sql)

    Regex.scan(pattern, sql)
    |> Enum.map(fn [_, variable] -> variable end)
    |> Enum.uniq()
    |> Enum.reject(fn var -> var in bound_variables end)
    |> Enum.map(fn variable ->
      %{
        variable: variable,
        table: primary_table,
        column: nil
      }
    end)
  end

  # Extract first table name from FROM clause
  defp guess_primary_table(sql) do
    case Regex.run(~r/from\s+(\w+)/i, sql) do
      [_, table] -> table
      nil -> nil
    end
  end
end
