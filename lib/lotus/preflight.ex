defmodule Lotus.Preflight do
  @moduledoc """
  SQL preflight authorization for Lotus.

  Uses EXPLAIN to extract which tables/relations a query will access,
  then checks those relations against visibility rules before execution.

  This provides defense-in-depth by blocking queries that would access
  denied tables, even if they're accessed through views or complex subqueries.
  """

  alias Lotus.Visibility

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
    unless Map.has_key?(Lotus.Config.data_repos(), repo_name) do
      {:error, "Unknown data repo '#{repo_name}'"}
    else
      case adapter(repo) do
        :postgres -> authorize_pg(repo, repo_name, sql, params, search_path)
        :sqlite -> authorize_sqlite(repo, repo_name, sql, params, search_path)
        # fallback: allow if unknown adapter
        _ -> :ok
      end
    end
  end

  defp adapter(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      _ -> :other
    end
  end

  defp authorize_pg(repo, repo_name, sql, params, search_path) do
    explain = "EXPLAIN (VERBOSE, FORMAT JSON) " <> sql

    result =
      if search_path do
        case repo.transaction(fn ->
               repo.query!("SET LOCAL search_path = #{search_path}")
               repo.query(explain, params)
             end) do
          {:ok, query_result} -> query_result
          {:error, err} -> {:error, err}
        end
      else
        repo.query(explain, params)
      end

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
          :ok
        else
          blocked_tables = Enum.reject(rels, &Visibility.allowed_relation?(repo_name, &1))
          {:error, "Query touches blocked table(s): #{format_relations(blocked_tables)}"}
        end

      {:error, e} ->
        {:error, normalize_preflight_error(e)}
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
          :ok
        else
          blocked = Enum.reject(rels, &Visibility.allowed_relation?(repo_name, &1))
          {:error, "Query touches blocked table(s): #{format_relations(blocked)}"}
        end

      {:error, e} ->
        {:error, normalize_preflight_error(e)}
    end
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
    |> Enum.join(", ")
  end

  defp normalize_preflight_error(e) do
    e
    |> Lotus.Adapter.format_error()
    |> strip_explain_query_tail()
  end

  # If a driver glued the SQL after the message (e.g. "\nquery: EXPLAIN ..."),
  # hide it so tests/users don't see our internal EXPLAIN wrapper.
  defp strip_explain_query_tail(msg) when is_binary(msg) do
    Regex.replace(~r/\n?query:\s*EXPLAIN[\s\S]*\z/i, msg, "")
    |> String.trim_trailing()
  end

  defp strip_explain_query_tail(msg), do: msg
end
