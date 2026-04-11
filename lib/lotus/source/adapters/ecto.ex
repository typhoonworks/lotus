defmodule Lotus.Source.Adapters.Ecto do
  @moduledoc """
  Adapter wrapping any `Ecto.Repo` module in the `Lotus.Source.Adapter` behaviour.

  Delegates database-specific operations to the existing source implementation
  modules (`Lotus.Sources.Postgres`, `Lotus.Sources.MySQL`, `Lotus.Sources.SQLite3`,
  `Lotus.Sources.Default`) based on the repo's underlying Ecto adapter.

  ## Usage

      adapter = Lotus.Source.Adapters.Ecto.wrap("main", MyApp.Repo)

      Lotus.Source.Adapter.execute_query(adapter, "SELECT 1", [], [])
      Lotus.Source.Adapter.list_schemas(adapter)

  The `state` field of the resulting `%Adapter{}` struct holds the repo module
  itself, since Ecto repos are statically supervised and don't require explicit
  connection management.
  """

  @behaviour Lotus.Source.Adapter

  alias Lotus.Source.Adapter
  alias Lotus.SQL.Sanitizer

  @impls %{
    Ecto.Adapters.Postgres => Lotus.Sources.Postgres,
    Ecto.Adapters.SQLite3 => Lotus.Sources.SQLite3,
    Ecto.Adapters.MyXQL => Lotus.Sources.MySQL
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Wraps an `Ecto.Repo` module in an `%Adapter{}` struct.

  The resulting adapter delegates all callbacks to the appropriate source
  implementation based on the repo's underlying Ecto adapter.

  ## Parameters

    * `name` — a human-readable identifier (e.g. `"main"`, `"warehouse"`)
    * `repo_module` — the Ecto.Repo module (e.g. `MyApp.Repo`)

  ## Examples

      iex> adapter = Lotus.Source.Adapters.Ecto.wrap("main", MyApp.Repo)
      %Lotus.Source.Adapter{name: "main", module: Lotus.Source.Adapters.Ecto, ...}
  """
  @spec wrap(String.t(), module()) :: Adapter.t()
  def wrap(name, repo_module) when is_binary(name) and is_atom(repo_module) do
    %Adapter{
      name: name,
      module: __MODULE__,
      state: repo_module,
      source_type: detect_source_type(repo_module)
    }
  end

  @doc """
  Detects the source type from a repo module's underlying Ecto adapter.

  ## Examples

      iex> Lotus.Source.Adapters.Ecto.detect_source_type(MyApp.Repo)
      :postgres
  """
  @spec detect_source_type(module()) :: Adapter.source_type()
  def detect_source_type(repo_module) when is_atom(repo_module) do
    case repo_module.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      Ecto.Adapters.MyXQL -> :mysql
      _ -> :other
    end
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Query Execution
  # ---------------------------------------------------------------------------

  @impl true
  def execute_query(repo, sql, params, opts) do
    timeout = Keyword.get(opts, :timeout, 15_000)
    search_path = Keyword.get(opts, :search_path)
    impl = impl_for(repo)

    impl.execute_in_transaction(
      repo,
      fn ->
        if search_path do
          impl.set_search_path(repo, search_path)
        end

        case repo.query(sql, params, timeout: timeout) do
          {:ok, %{columns: cols, rows: rows} = raw} ->
            num_rows = Map.get(raw, :num_rows, length(rows || []))

            result =
              %{columns: cols, rows: rows, num_rows: num_rows}
              |> maybe_put(:command, Map.get(raw, :command))
              |> maybe_put(:connection_id, Map.get(raw, :connection_id))
              |> maybe_put(:messages, Map.get(raw, :messages))

            result

          {:error, err} ->
            repo.rollback(impl.format_error(err))
        end
      end,
      opts
    )
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def transaction(repo, fun, opts) do
    impl_for(repo).execute_in_transaction(repo, fn -> fun.(repo) end, opts)
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Introspection (wrap bare returns in {:ok, _} tuples)
  # ---------------------------------------------------------------------------

  @impl true
  def list_schemas(repo) do
    {:ok, impl_for(repo).list_schemas(repo)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def list_tables(repo, schemas, opts) do
    include_views? = Keyword.get(opts, :include_views, false)
    {:ok, impl_for(repo).list_tables(repo, schemas, include_views?)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def get_table_schema(repo, schema, table) do
    {:ok, impl_for(repo).get_table_schema(repo, schema, table)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def resolve_table_schema(repo, table, schemas) do
    {:ok, impl_for(repo).resolve_table_schema(repo, table, schemas)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ---------------------------------------------------------------------------
  # Callbacks — SQL Generation (delegate to source impl via state)
  # ---------------------------------------------------------------------------

  @impl true
  def quote_identifier(repo, identifier) do
    impl_for(repo).quote_identifier(identifier)
  end

  @impl true
  def param_placeholder(repo, index, var, type) do
    impl_for(repo).param_placeholder(index, var, type)
  end

  @impl true
  def limit_offset_placeholders(repo, limit_index, offset_index) do
    impl_for(repo).limit_offset_placeholders(limit_index, offset_index)
  end

  @impl true
  def apply_filters(repo, sql, params, filters) do
    impl_for(repo).apply_filters(sql, params, filters)
  end

  @impl true
  def apply_sorts(repo, sql, sorts) do
    impl_for(repo).apply_sorts(sql, sorts)
  end

  @impl true
  def explain_plan(repo, sql, params, opts) do
    impl_for(repo).explain_plan(repo, sql, params, opts)
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Safety & Visibility (delegate to source impl)
  # ---------------------------------------------------------------------------

  @impl true
  def builtin_denies(repo) do
    impl_for(repo).builtin_denies(repo)
  end

  @impl true
  def builtin_schema_denies(repo) do
    impl_for(repo).builtin_schema_denies(repo)
  end

  @impl true
  def default_schemas(repo) do
    impl_for(repo).default_schemas(repo)
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def health_check(repo) do
    case repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, err}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def disconnect(_repo) do
    # Static repos are managed by the application supervisor.
    :ok
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Error Handling
  # ---------------------------------------------------------------------------

  @impl true
  def format_error(_repo, error) do
    impl_for_error(error).format_error(error)
  end

  @impl true
  def handled_errors(repo) do
    impl_for(repo).handled_errors()
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Pipeline (Query Processing)
  # ---------------------------------------------------------------------------

  # Deny list for dangerous operations (defense-in-depth).
  # Skipped when `read_only: false` is passed in opts.
  @deny ~r/\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|VACUUM|ANALYZE|CALL|LOCK)\b/i

  @impl true
  def sanitize_query(_repo, query, opts) do
    read_only = Keyword.get(opts, :read_only, true)

    with :ok <- assert_single_statement(query) do
      assert_not_denied(query, read_only)
    end
  end

  @impl true
  def transform_query(_repo, query, params, _opts), do: {query, params}

  @impl true
  def extract_accessed_resources(repo, query, params, opts) do
    source_type = detect_source_type(repo)
    search_path = Keyword.get(opts, :search_path)

    case source_type do
      :postgres -> extract_pg_resources(repo, query, params, search_path)
      :sqlite -> extract_sqlite_resources(repo, query, params)
      :mysql -> extract_mysql_resources(repo, query, params)
      _ -> :skip
    end
  end

  @impl true
  def apply_window(repo, query, params, window_opts) do
    base_sql = Sanitizer.strip_trailing_semicolon(query)
    limit = Keyword.fetch!(window_opts, :limit)
    offset = Keyword.get(window_opts, :offset, 0)
    count_mode = Keyword.get(window_opts, :count, :none)
    search_path = Keyword.get(window_opts, :search_path)

    param_count = length(params)

    {limit_ph, offset_ph} =
      impl_for(repo).limit_offset_placeholders(param_count + 1, param_count + 2)

    paged_sql =
      "SELECT * FROM (" <>
        base_sql <> ") AS lotus_sub LIMIT " <> limit_ph <> " OFFSET " <> offset_ph

    paged_params = params ++ [limit, offset]

    window_meta =
      case count_mode do
        :exact ->
          adapter_struct = wrap("__window__", repo)

          %{
            window: %{limit: limit, offset: offset},
            total_count: :pending,
            total_mode: :exact,
            count_sql: "SELECT COUNT(*) FROM (" <> base_sql <> ") AS lotus_sub",
            count_params: params,
            adapter: adapter_struct,
            search_path: search_path
          }

        _ ->
          %{window: %{limit: limit, offset: offset}, total_count: nil, total_mode: :none}
      end

    {paged_sql, paged_params, window_meta}
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Source Identity
  # ---------------------------------------------------------------------------

  @impl true
  def source_type(repo), do: detect_source_type(repo)

  @impl true
  def supports_feature?(repo, feature) do
    source = detect_source_type(repo)
    Lotus.Sources.supports_feature?(source, feature)
  end

  @impl true
  def query_language(repo), do: impl_for(repo).query_language()

  @impl true
  def limit_query(repo, statement, limit), do: impl_for(repo).limit_query(statement, limit)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp impl_for(repo) do
    source_mod = repo.__adapter__()
    Map.get(@impls, source_mod, Lotus.Sources.Default)
  end

  defp impl_for_error(%{__exception__: true, __struct__: exc_mod}) do
    Enum.find_value(
      Map.values(@impls) ++ [Lotus.Sources.Default],
      Lotus.Sources.Default,
      fn impl ->
        if exc_mod in impl.handled_errors(), do: impl, else: false
      end
    )
  end

  defp impl_for_error(_), do: Lotus.Sources.Default

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Sanitization helpers
  # ---------------------------------------------------------------------------

  # Allow a single statement with an optional trailing semicolon.
  # Reject any additional top-level semicolons (outside strings/comments).
  defp assert_single_statement(sql) do
    s = String.trim(sql)

    s =
      if String.ends_with?(s, ";") do
        s
        |> String.trim_trailing()
        |> String.trim_trailing(";")
        |> String.trim_trailing()
      else
        s
      end

    if has_top_level_semicolon?(s) do
      {:error, "Only a single statement is allowed"}
    else
      :ok
    end
  end

  defp has_top_level_semicolon?(bin), do: scan_semicolons(bin, :code)

  # State machine that skips semicolons inside:
  # - single-quoted strings
  # - double-quoted identifiers
  # - PostgreSQL dollar-quoted strings ($tag$ ... $tag$ or $ ... $)
  # - line comments (-- ...\n)
  # - block comments (/* ... */)
  defp scan_semicolons(<<>>, _state), do: false

  defp scan_semicolons(<<?;, _::binary>>, :code), do: true

  defp scan_semicolons(<<"--", rest::binary>>, :code),
    do: scan_semicolons(skip_to_eol(rest), :code)

  defp scan_semicolons(<<"/*", rest::binary>>, :code),
    do: scan_semicolons(skip_block_comment(rest), :code)

  defp scan_semicolons(<<"'", rest::binary>>, :code),
    do: scan_semicolons(skip_single_quoted(rest), :code)

  defp scan_semicolons(<<"\"", rest::binary>>, :code),
    do: scan_semicolons(skip_double_quoted(rest), :code)

  defp scan_semicolons(<<"$", rest::binary>>, :code) do
    case take_dollar_tag(rest, "") do
      {:tag, tag, after_tag} -> scan_semicolons(skip_dollar_quoted(after_tag, tag), :code)
      :no_tag -> scan_semicolons(rest, :code)
    end
  end

  defp scan_semicolons(<<_::utf8, rest::binary>>, :code),
    do: scan_semicolons(rest, :code)

  defp skip_to_eol(<<>>), do: <<>>
  defp skip_to_eol(<<"\n", rest::binary>>), do: rest
  defp skip_to_eol(<<_::utf8, rest::binary>>), do: skip_to_eol(rest)

  defp skip_block_comment(rest), do: skip_block_comment(rest, 1)

  defp skip_block_comment(<<>>, _depth), do: <<>>
  defp skip_block_comment(<<"*/", rest::binary>>, 1), do: rest
  defp skip_block_comment(<<"*/", rest::binary>>, depth), do: skip_block_comment(rest, depth - 1)
  defp skip_block_comment(<<"/*", rest::binary>>, depth), do: skip_block_comment(rest, depth + 1)
  defp skip_block_comment(<<_::utf8, rest::binary>>, depth), do: skip_block_comment(rest, depth)

  defp skip_single_quoted(<<>>), do: <<>>
  defp skip_single_quoted(<<"''", rest::binary>>), do: skip_single_quoted(rest)
  defp skip_single_quoted(<<"'", rest::binary>>), do: rest
  defp skip_single_quoted(<<_::utf8, rest::binary>>), do: skip_single_quoted(rest)

  defp skip_double_quoted(<<>>), do: <<>>
  defp skip_double_quoted(<<"\"\"", rest::binary>>), do: skip_double_quoted(rest)
  defp skip_double_quoted(<<"\"", rest::binary>>), do: rest
  defp skip_double_quoted(<<_::utf8, rest::binary>>), do: skip_double_quoted(rest)

  defp take_dollar_tag(<<"$", rest::binary>>, acc), do: {:tag, acc, rest}

  defp take_dollar_tag(<<c, rest::binary>>, acc)
       when c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?_,
       do: take_dollar_tag(rest, <<acc::binary, c>>)

  defp take_dollar_tag(_, _), do: :no_tag

  defp skip_dollar_quoted(bin, tag) do
    closer = "$" <> tag <> "$"

    case :binary.match(bin, closer) do
      :nomatch -> <<>>
      {pos, len} -> :binary.part(bin, pos + len, byte_size(bin) - pos - len)
    end
  end

  defp assert_not_denied(_sql, false = _read_only), do: :ok

  defp assert_not_denied(sql, _read_only) do
    if Regex.match?(@deny, sql), do: {:error, "Only read-only queries are allowed"}, else: :ok
  end

  # ---------------------------------------------------------------------------
  # Resource extraction helpers
  # ---------------------------------------------------------------------------

  defp extract_pg_resources(repo, sql, params, search_path) do
    explain = "EXPLAIN (VERBOSE, FORMAT JSON) " <> sql
    opts = if search_path, do: [search_path: search_path], else: []

    case execute_query(repo, explain, params, opts) do
      {:ok, %{rows: [[json]]}} ->
        relations =
          json
          |> parse_pg_explain_plan()
          |> collect_pg_relations(MapSet.new())

        {:ok, relations}

      {:error, e} ->
        {:error, e}
    end
  end

  defp parse_pg_explain_plan(json) do
    plan_data =
      case json do
        binary when is_binary(binary) -> Lotus.JSON.decode!(binary)
        data when is_list(data) or is_map(data) -> data
      end

    case plan_data do
      [first | _] -> Map.fetch!(first, "Plan")
      %{"Plan" => plan} -> plan
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

  defp extract_sqlite_resources(repo, sql, params) do
    alias_map = parse_alias_map(sql)

    explain = "EXPLAIN QUERY PLAN " <> sql

    case execute_query(repo, explain, params, []) do
      {:ok, %{rows: rows}} ->
        relations =
          rows
          |> Enum.map(fn row -> Enum.join(row, " ") end)
          |> Enum.flat_map(&extract_sqlite_relations/1)
          |> Enum.map(&resolve_alias(&1, alias_map))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&{nil, &1})
          |> MapSet.new()

        {:ok, relations}

      {:error, e} ->
        {:error, e}
    end
  end

  defp extract_mysql_resources(repo, sql, params) do
    alias_map = parse_alias_map(sql)

    explain = "EXPLAIN FORMAT=JSON " <> sql

    case execute_query(repo, explain, params, []) do
      {:ok, %{rows: [[json]]}} ->
        explain_rels =
          json
          |> Lotus.JSON.decode!()
          |> collect_mysql_relations(MapSet.new())
          |> MapSet.to_list()
          |> Enum.map(fn {schema, table_name} ->
            {schema, resolve_alias(table_name, alias_map)}
          end)
          |> Enum.reject(fn {_schema, name} -> is_nil(name) end)

        sql_rels = extract_mysql_tables_from_sql(sql)
        relations = choose_mysql_relations(explain_rels, sql_rels, sql) |> MapSet.new()

        {:ok, relations}

      {:error, e} ->
        {:error, e}
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

  defp extract_mysql_tables_from_sql(sql) do
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

  defp parse_alias_map(sql) do
    s = strip_sql_comments(sql)

    rx_from = ~r/\bFROM\s+("?[A-Za-z0-9_]+"?)\s+(?:AS\s+)?("?[A-Za-z0-9_]+"?)/i
    rx_join = ~r/\bJOIN\s+("?[A-Za-z0-9_]+"?)\s+(?:AS\s+)?("?[A-Za-z0-9_]+"?)/i

    [rx_from, rx_join]
    |> Enum.flat_map(&Regex.scan(&1, s))
    |> Enum.reduce(%{}, fn
      [_, base, alias_name], acc ->
        base = normalize_ident(base)
        alias_name = normalize_ident(alias_name)
        if base == "(", do: acc, else: Map.put(acc, alias_name, base)

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
end
