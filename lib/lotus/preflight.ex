defmodule Lotus.Preflight do
  @moduledoc """
  SQL preflight authorization for Lotus.

  Uses EXPLAIN to extract which tables/relations a query will access,
  then checks those relations against visibility rules before execution.

  This provides defense-in-depth by blocking queries that would access
  denied tables, even if they're accessed through views or complex subqueries.
  """

  alias Lotus.Visibility
  alias Lotus.Sources
  alias Lotus.Preflight.Relations

  @doc """
  Authorizes a SQL query by checking all relations it would access.

  Uses EXPLAIN (without executing) to discover which tables the query
  would touch, then validates each against the visibility rules.

  ## Examples

      authorize(MyRepo, "postgres", "SELECT * FROM users", [], nil)
      #=> :ok

      authorize(MyRepo, "postgres", "SELECT * FROM schema_migrations", [], "reporting, public")
      #=> {:error, "Query touches a blocked table"}
  """
  @spec authorize(module(), String.t(), String.t(), list(), String.t() | nil) ::
          :ok | {:error, String.t()}
  def authorize(repo, repo_name, sql, params, search_path \\ nil) do
    if Map.has_key?(Lotus.Config.data_repos(), repo_name) do
      case Sources.source_type(repo) do
        :postgres -> authorize_pg(repo, repo_name, sql, params, search_path)
        :sqlite -> authorize_sqlite(repo, repo_name, sql, params, search_path)
        :mysql -> authorize_mysql(repo, repo_name, sql, params, search_path)
        _ -> :ok
      end
    else
      {:error, "Unknown data repo '#{repo_name}'"}
    end
  end

  defp authorize_pg(repo, repo_name, sql, params, search_path) do
    explain = "EXPLAIN (VERBOSE, FORMAT JSON) " <> sql
    result = execute_pg_explain(repo, explain, params, search_path)

    case result do
      {:ok, %{rows: [[json]]}} ->
        plan_data =
          case json do
            binary when is_binary(binary) -> Lotus.JSON.decode!(binary)
            data when is_list(data) or is_map(data) -> data
          end

        plan =
          case plan_data do
            [first | _] -> Map.fetch!(first, "Plan")
            %{"Plan" => plan} -> plan
          end

        rels = collect_pg_relations(plan, MapSet.new()) |> MapSet.to_list()

        if Enum.all?(rels, &Visibility.allowed_relation?(repo_name, &1)) do
          Relations.put(rels)
          :ok
        else
          blocked_tables = Enum.reject(rels, &Visibility.allowed_relation?(repo_name, &1))
          {:error, "Query touches blocked table(s): #{format_relations(blocked_tables)}"}
        end

      {:error, e} ->
        {:error, normalize_preflight_error(e)}
    end
  end

  defp execute_pg_explain(repo, explain, params, nil) do
    repo.query(explain, params)
  end

  defp execute_pg_explain(repo, explain, params, search_path) do
    result =
      repo.transaction(fn ->
        repo.query!("SET LOCAL search_path = #{search_path}")
        repo.query(explain, params)
      end)

    case result do
      {:ok, query_result} -> query_result
      {:error, err} -> {:error, err}
    end
  end

  defp collect_pg_relations(%{"Plans" => plans} = node, acc) do
    Enum.reduce(plans, collect_pg_here(node, acc), &collect_pg_relations/2)
  end

  defp collect_pg_relations(node, acc), do: collect_pg_here(node, acc)

  defp collect_pg_here(node, acc) do
    case {node["Schema"], node["Relation Name"]} do
      {schema, rel} when is_binary(schema) and is_binary(rel) ->
        MapSet.put(acc, {schema, rel})

      _ ->
        acc
    end
  end

  defp authorize_sqlite(repo, repo_name, sql, params, _search_path) do
    alias_map = parse_alias_map(sql)

    explain = "EXPLAIN QUERY PLAN " <> sql

    case repo.query(explain, params) do
      {:ok, %{rows: rows}} ->
        rels =
          rows
          |> Enum.map(fn row -> Enum.join(row, " ") end)
          # names (base or alias)
          |> Enum.flat_map(&extract_sqlite_relations/1)
          # <— rewrite alias -> base
          |> Enum.map(&resolve_alias(&1, alias_map))
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()
          |> MapSet.to_list()
          |> Enum.map(&{nil, &1})

        if Enum.all?(rels, &Visibility.allowed_relation?(repo_name, &1)) do
          Relations.put(rels)
          :ok
        else
          blocked = Enum.reject(rels, &Visibility.allowed_relation?(repo_name, &1))
          {:error, "Query touches blocked table(s): #{format_relations(blocked)}"}
        end

      {:error, e} ->
        {:error, normalize_preflight_error(e)}
    end
  end

  defp authorize_mysql(repo, repo_name, sql, params, _search_path) do
    alias_map = parse_alias_map(sql)

    explain = "EXPLAIN FORMAT=JSON " <> sql

    case repo.query(explain, params) do
      {:ok, %{rows: [[json]]}} ->
        plan_data = Lotus.JSON.decode!(json)

        explain_rels =
          plan_data
          |> collect_mysql_relations(MapSet.new())
          |> MapSet.to_list()
          |> Enum.map(fn {schema, table_name} ->
            actual_name = resolve_alias(table_name, alias_map)
            {schema, actual_name}
          end)
          |> Enum.reject(fn {_schema, name} -> is_nil(name) end)

        sql_rels = extract_mysql_tables_from_sql(sql)

        rels = choose_mysql_relations(explain_rels, sql_rels, sql)

        if Enum.all?(rels, &Visibility.allowed_relation?(repo_name, &1)) do
          Relations.put(rels)
          :ok
        else
          blocked = Enum.reject(rels, &Visibility.allowed_relation?(repo_name, &1))
          {:error, "Query touches blocked table(s): #{format_relations(blocked)}"}
        end

      {:error, e} ->
        {:error, normalize_preflight_error(e)}
    end
  end

  defp collect_mysql_relations(%{"query_block" => query_block}, acc) do
    collect_mysql_query_block(query_block, acc)
  end

  defp collect_mysql_relations(data, acc) when is_list(data) do
    Enum.reduce(data, acc, &collect_mysql_relations/2)
  end

  defp collect_mysql_relations(data, acc) when is_map(data) do
    case Map.get(data, "query_block") do
      nil -> acc
      query_block -> collect_mysql_query_block(query_block, acc)
    end
  end

  defp collect_mysql_relations(_, acc), do: acc

  defp collect_mysql_query_block(%{"table" => table_info}, acc) when is_map(table_info) do
    case Map.get(table_info, "table_name") do
      table_name when is_binary(table_name) ->
        schema = Map.get(table_info, "schema")
        MapSet.put(acc, {schema, table_name})

      _ ->
        acc
    end
  end

  defp collect_mysql_query_block(%{"nested_loop" => nested_loop}, acc)
       when is_list(nested_loop) do
    Enum.reduce(nested_loop, acc, fn item, acc_inner ->
      collect_mysql_query_block(item, acc_inner)
    end)
  end

  defp collect_mysql_query_block(data, acc) when is_map(data) do
    data
    |> Enum.reduce(acc, fn {_key, value}, acc_inner ->
      collect_mysql_relations(value, acc_inner)
    end)
  end

  defp collect_mysql_query_block(_, acc), do: acc

  # Extract table names directly from SQL when EXPLAIN aliases fail
  defp extract_mysql_tables_from_sql(sql) do
    # Look for schema.table and table patterns in FROM/JOIN clauses
    table_regex =
      ~r/(?:FROM|JOIN)\s+(?:(`?)([a-zA-Z_][a-zA-Z0-9_]*)\1\.)?(`?)([a-zA-Z_][a-zA-Z0-9_]*)\3(?:\s+(?:AS\s+)?[a-zA-Z_][a-zA-Z0-9_]*)?/i

    Regex.scan(table_regex, sql)
    |> Enum.map(fn
      [_, _, schema, _, table] when schema != "" -> {schema, table}
      [_, "", "", _, table] -> {nil, table}
    end)
    |> Enum.uniq()
  end

  defp choose_mysql_relations(explain_rels, sql_rels, sql) do
    if should_use_sql_relations?(explain_rels, sql) do
      sql_rels
    else
      explain_rels
    end
  end

  defp should_use_sql_relations?(explain_rels, sql) do
    Enum.empty?(explain_rels) or
      Enum.all?(explain_rels, fn {_, name} -> String.length(name) <= 4 end) or
      String.contains?(sql, "information_schema") or
      String.contains?(sql, "performance_schema") or
      String.contains?(sql, "mysql.") or
      String.contains?(sql, "sys.")
  end

  # Map of alias -> base table derived from SQL text.
  # Handles: FROM t a | FROM t AS a | JOIN t a | JOIN t AS a (quoted or not).
  # Ignores subquery aliases like FROM (SELECT ...) a.
  defp parse_alias_map(sql) do
    s = strip_sql_comments(sql)

    rx_from = ~r/\bFROM\s+("?[A-Za-z0-9_]+"?)\s+(?:AS\s+)?("?[A-Za-z0-9_]+"?)/i
    rx_join = ~r/\bJOIN\s+("?[A-Za-z0-9_]+"?)\s+(?:AS\s+)?("?[A-Za-z0-9_]+"?)/i

    [rx_from, rx_join]
    |> Enum.flat_map(&Regex.scan(&1, s))
    |> Enum.reduce(%{}, fn
      [_, base, alias], acc ->
        base = normalize_ident(base)
        alias = normalize_ident(alias)
        if base == "(", do: acc, else: Map.put(acc, alias, base)

      _, acc ->
        acc
    end)
  end

  defp strip_sql_comments(s) do
    s
    |> String.replace(~r/--.*$/m, "")
    |> String.replace(~r/\/\*[\s\S]*?\*\//, "")
  end

  defp normalize_ident(<<"\"", rest::binary>>) do
    rest |> String.trim_trailing(~s|"|) |> String.replace(~s|""|, ~s|"|)
  end

  defp normalize_ident(s), do: s

  defp resolve_alias(name, alias_map), do: Map.get(alias_map, name, name)

  # Extract relation tokens from plan lines.
  # Covers:
  #   SCAN/SEARCH TABLE <base> AS <alias>    -> capture <base>
  #   SCAN/SEARCH TABLE <base>               -> capture <base>
  #   SCAN/SEARCH <name>                     -> capture <name> (alias or base; remapped later)
  defp extract_sqlite_relations(text) do
    cond do
      Regex.match?(
        ~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)\s+AS\s+("[^"]+"|[A-Za-z0-9_]+)/,
        text
      ) ->
        for [_, base, _alias] <-
              Regex.scan(
                ~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)\s+AS\s+("[^"]+"|[A-Za-z0-9_]+)/,
                text
              ) do
          normalize_ident(base)
        end

      Regex.match?(~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)/, text) ->
        for [_, base] <- Regex.scan(~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)/, text) do
          normalize_ident(base)
        end

      Regex.match?(~r/\b(?:SCAN|SEARCH)\s+("[^"]+"|[A-Za-z0-9_]+)/, text) ->
        for [_, name] <- Regex.scan(~r/\b(?:SCAN|SEARCH)\s+("[^"]+"|[A-Za-z0-9_]+)/, text) do
          normalize_ident(name)
        end

      true ->
        []
    end
  end

  defp format_relations(relations) do
    relations
    |> Enum.map(fn
      {nil, table} -> table
      {schema, table} -> "#{schema}.#{table}"
    end)
  end

  defp normalize_preflight_error(e) do
    e
    |> Lotus.Source.format_error()
    |> strip_explain_query_tail()
  end

  # If a driver glued the SQL after the message (e.g. "\nquery: EXPLAIN ..."),
  # hide it so tests/users don't see our internal EXPLAIN wrapper.
  defp strip_explain_query_tail(msg) do
    Regex.replace(~r/\n?query:\s*EXPLAIN[\s\S]*\z/i, msg, "")
    |> String.trim_trailing()
  end
end
