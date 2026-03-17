defmodule Lotus.Schema do
  @moduledoc """
  Schema introspection functionality for Lotus.

  Provides functions to list schemas, tables and inspect table schemas across
  different database adapters (PostgreSQL, MySQL, SQLite, etc.).

  ## Visibility Filtering

  All schema and table listing functions automatically apply visibility rules
  configured in your application:

  - **Schema visibility** filters which schemas are accessible
  - **Table visibility** filters which tables within allowed schemas are accessible
  - **Built-in security** automatically blocks system schemas and tables

  Schema visibility takes precedence - if a schema is denied, all tables within it
  are blocked regardless of table-level rules.

  ## Database-Specific Behavior

  - **PostgreSQL**: Returns namespaced `{schema, table}` tuples
  - **MySQL**: Returns `{database, table}` tuples (schemas = databases in MySQL)
  - **SQLite**: Returns table names as strings (schema-less)
  """

  alias Lotus.{Config, Middleware, Sources, Telemetry, Visibility}
  alias Lotus.Source.Adapter
  alias Lotus.Visibility.Policy

  @doc """
  Lists all visible schemas in the given repository.

  Returns a list of schema names filtered by visibility rules. For databases
  without schemas (like SQLite), returns an empty list.

  **Note**: Results are automatically filtered by schema visibility rules.
  System schemas (like `pg_catalog`) are always blocked for security.

  ## Options

  - `:cache` - Cache options (profile, ttl_ms, etc.)

  ## Examples

      {:ok, schemas} = Lotus.Schema.list_schemas(MyApp.Repo)
      # PostgreSQL: ["public", "reporting", ...]  (filtered by visibility)

      {:ok, schemas} = Lotus.Schema.list_schemas("mysql")
      # MySQL: ["app_production", "analytics_db", ...]  (databases = schemas)

      {:ok, schemas} = Lotus.Schema.list_schemas("sqlite")
      # SQLite: []  (schema-less database)
  """
  @spec list_schemas(module() | String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def list_schemas(repo_or_name, opts \\ []) do
    adapter = Sources.resolve!(repo_or_name, nil)
    context = Keyword.get(opts, :context)
    start_time = Telemetry.schema_introspection_start(:list_schemas, adapter.name)

    key = schema_key(:list_schemas, adapter.name)
    tags = ["repo:#{adapter.name}", "schema:list_schemas"]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :schema)
      else
        :schema
      end

    result =
      exec_with_cache(opts[:cache], profile, key, tags, fn ->
        try do
          case Adapter.list_schemas(adapter) do
            {:ok, raw_schemas} ->
              filtered_schemas = Visibility.filter_schemas(raw_schemas, adapter.name)

              run_after_discover(:after_list_schemas, :schemas, %{
                repo: adapter.name,
                repo_name: adapter.name,
                schemas: filtered_schemas,
                context: context
              })

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    Telemetry.schema_introspection_stop(
      start_time,
      :list_schemas,
      adapter.name,
      result_status(result)
    )

    result
  end

  @doc """
  Lists all visible tables in the given repository.

  For databases with schemas (like PostgreSQL), returns {schema, table} tuples.
  For databases without schemas (like SQLite), returns just table names as strings.

  **Note**: Results are automatically filtered by visibility rules:

  1. Schema visibility is checked first - denied schemas block all their tables
  2. Table visibility is then applied to tables in allowed schemas
  3. System tables are always blocked for security

  ## Options

  - `:schema` - Search in specific schema (e.g., `schema: "reporting"`)
  - `:schemas` - Search in multiple schemas (e.g., `schemas: ["reporting", "public"]`)
  - `:search_path` - Use PostgreSQL search_path (e.g., `search_path: "reporting, public"`)
  - `:include_views` - Include views in results (default: false)

  ## Examples

      {:ok, tables} = Lotus.Schema.list_tables(MyApp.Repo)
      # PostgreSQL: [{"public", "users"}, {"public", "posts"}, ...]  (filtered by visibility)

      {:ok, tables} = Lotus.Schema.list_tables("postgres", search_path: "reporting, public")
      # PostgreSQL: [{"reporting", "customers"}, {"reporting", "orders"}, {"public", "users"}, ...]

      {:ok, tables} = Lotus.Schema.list_tables("mysql")
      # MySQL: [{"app_db", "users"}, {"analytics_db", "reports"}, ...]  (databases = schemas)

      {:ok, tables} = Lotus.Schema.list_tables("sqlite")
      # SQLite: ["products", "orders", "order_items"]  (schema-less)
  """
  @spec list_tables(module() | String.t(), keyword()) ::
          {:ok, [{String.t(), String.t()}] | [String.t()]} | {:error, term()}
  def list_tables(repo_or_name, opts \\ []) do
    adapter = Sources.resolve!(repo_or_name, nil)
    context = Keyword.get(opts, :context)
    start_time = Telemetry.schema_introspection_start(:list_tables, adapter.name)
    schemas = effective_schemas(adapter, opts)
    include_views? = Keyword.get(opts, :include_views, false)

    result =
      case Visibility.validate_schemas(schemas, adapter.name) do
        :ok ->
          search_path = Keyword.get(opts, :search_path)

          key =
            schema_key(
              :list_tables,
              adapter.name,
              search_path || Enum.join(schemas, ","),
              include_views?
            )

          tags = ["repo:#{adapter.name}", "schema:list_tables"]

          profile =
            if is_list(opts[:cache]) do
              Keyword.get(opts[:cache], :profile, :schema)
            else
              :schema
            end

          exec_with_cache(opts[:cache], profile, key, tags, fn ->
            try do
              case Adapter.list_tables(adapter, schemas, include_views: include_views?) do
                {:ok, raw_relations} ->
                  filtered =
                    raw_relations
                    |> Enum.filter(&Visibility.allowed_relation?(adapter.name, &1))

                  tables =
                    if Enum.all?(filtered, fn {schema, _table} -> is_nil(schema) end) do
                      Enum.map(filtered, fn {nil, table} -> table end)
                    else
                      filtered
                    end

                  run_after_discover(:after_list_tables, :tables, %{
                    repo: adapter.name,
                    repo_name: adapter.name,
                    tables: tables,
                    context: context
                  })

                {:error, reason} ->
                  {:error, reason}
              end
            rescue
              e -> {:error, Exception.message(e)}
            end
          end)

        {:error, :schema_not_visible, denied: denied} ->
          {:error, "Schema(s) not visible: #{Enum.join(denied, ", ")}"}
      end

    Telemetry.schema_introspection_stop(
      start_time,
      :list_tables,
      adapter.name,
      result_status(result)
    )

    result
  end

  @doc """
  Gets the schema information for a specific table.

  Returns a list of column definitions with their types and constraints.

  ## Options

  - `:schema` - Look for table in specific schema
  - `:schemas` - Search for table in multiple schemas (first match wins)
  - `:search_path` - Use PostgreSQL search_path to resolve table location
  - `:cache` - Cache options (profile, ttl_ms, etc.)

  ## Examples

      {:ok, schema} = Lotus.Schema.get_table_schema(MyApp.Repo, "users")
      # Returns schema for public.users

      {:ok, schema} = Lotus.Schema.get_table_schema("postgres", "customers", schema: "reporting")
      # Returns schema for reporting.customers

      {:ok, schema} = Lotus.Schema.get_table_schema("postgres", "customers", search_path: "reporting, public")
      # Finds customers table using search_path resolution
  """
  @spec get_table_schema(module() | String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_table_schema(repo_or_name, table_name, opts \\ []) do
    adapter = Sources.resolve!(repo_or_name, nil)
    context = Keyword.get(opts, :context)
    start_time = Telemetry.schema_introspection_start(:get_table_schema, adapter.name)
    schemas = effective_schemas(adapter, opts)

    result =
      case resolve_table_schema_with_cache(
             adapter,
             table_name,
             schemas,
             opts[:cache],
             :schema
           ) do
        nil when schemas == [] ->
          # Schema-less database (SQLite) - nil is expected, proceed with nil schema
          get_table_schema_cached(adapter, table_name, nil, context, opts)

        nil ->
          {:error, "Table '#{table_name}' not found in schemas: #{Enum.join(schemas, ", ")}"}

        resolved_schema ->
          get_table_schema_cached(adapter, table_name, resolved_schema, context, opts)
      end

    Telemetry.schema_introspection_stop(
      start_time,
      :get_table_schema,
      adapter.name,
      result_status(result)
    )

    result
  end

  defp get_table_schema_cached(adapter, table_name, resolved_schema, context, opts) do
    key = schema_key(:get_table_schema, adapter.name, resolved_schema, table_name)

    tags = [
      "repo:#{adapter.name}",
      "schema:get_table_schema",
      "table:#{if resolved_schema, do: "#{resolved_schema}.#{table_name}", else: table_name}"
    ]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :schema)
      else
        :schema
      end

    exec_with_cache(opts[:cache], profile, key, tags, fn ->
      if Visibility.allowed_relation?(adapter.name, {resolved_schema, table_name}) do
        fetch_and_annotate_columns(adapter, resolved_schema, table_name, context)
      else
        {:error, table_not_visible_message(resolved_schema, table_name)}
      end
    end)
  end

  defp fetch_and_annotate_columns(adapter, resolved_schema, table_name, context) do
    case Adapter.get_table_schema(adapter, resolved_schema, table_name) do
      {:ok, cols} ->
        annotated =
          annotate_columns_with_visibility(cols, adapter.name, resolved_schema, table_name)

        run_after_discover(:after_get_table_schema, :columns, %{
          repo: adapter.name,
          repo_name: adapter.name,
          table_name: table_name,
          schema: resolved_schema,
          columns: annotated,
          context: context
        })

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp annotate_columns_with_visibility(cols, source_name, schema, table_name) do
    rels = [{schema, table_name}]

    cols
    |> Enum.reduce([], fn col, acc ->
      policy = Visibility.column_policy_for(source_name, rels, col.name)

      cond do
        Policy.hidden_from_schema?(policy) -> acc
        is_map(policy) -> [Map.put(col, :visibility, Map.take(policy, [:action, :mask])) | acc]
        true -> [col | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp table_not_visible_message(nil, table_name),
    do: "Table '#{table_name}' is not visible by Lotus policy"

  defp table_not_visible_message(schema, table_name),
    do: "Table '#{schema}.#{table_name}' is not visible by Lotus policy"

  @doc """
  Gets basic statistics about a table.

  Returns information like row count and table size.

  ## Options

  - `:schema` - Look for table in specific schema
  - `:schemas` - Search for table in multiple schemas (first match wins)
  - `:search_path` - Use PostgreSQL search_path to resolve table location
  - `:cache` - Cache options (profile, ttl_ms, etc.)

  ## Examples

      {:ok, stats} = Lotus.Schema.get_table_stats(MyApp.Repo, "users")
      # Returns: %{row_count: 1234}

      {:ok, stats} = Lotus.Schema.get_table_stats("postgres", "customers", schema: "reporting")
      # Gets stats for reporting.customers
  """
  @spec get_table_stats(module() | String.t(), String.t(), keyword()) ::
          {:ok, %{row_count: non_neg_integer()}} | {:error, binary()}
  def get_table_stats(repo_or_name, table_name, opts \\ []) do
    adapter = Sources.resolve!(repo_or_name, nil)
    start_time = Telemetry.schema_introspection_start(:get_table_stats, adapter.name)
    schemas = effective_schemas(adapter, opts)

    result =
      case resolve_table_schema_with_cache(
             adapter,
             table_name,
             schemas,
             opts[:cache],
             :results
           ) do
        nil when schemas == [] ->
          get_table_stats_cached(adapter, table_name, nil, opts)

        nil ->
          {:error, "Table '#{table_name}' not found in schemas: #{Enum.join(schemas, ", ")}"}

        resolved_schema ->
          get_table_stats_cached(adapter, table_name, resolved_schema, opts)
      end

    Telemetry.schema_introspection_stop(
      start_time,
      :get_table_stats,
      adapter.name,
      result_status(result)
    )

    result
  end

  defp get_table_stats_cached(adapter, table_name, resolved_schema, opts) do
    key = schema_key(:get_table_stats, adapter.name, resolved_schema, table_name)

    tags = [
      "repo:#{adapter.name}",
      "schema:get_table_stats",
      "table:#{if resolved_schema, do: "#{resolved_schema}.#{table_name}", else: table_name}"
    ]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :results)
      else
        :results
      end

    exec_with_cache(opts[:cache], profile, key, tags, fn ->
      if Visibility.allowed_relation?(adapter.name, {resolved_schema, table_name}) do
        try do
          count_sql =
            if resolved_schema do
              qi = &Adapter.quote_identifier(adapter, &1)
              "SELECT COUNT(*) FROM #{qi.(resolved_schema)}.#{qi.(table_name)}"
            else
              "SELECT COUNT(*) FROM #{table_name}"
            end

          case Adapter.execute_query(adapter, count_sql, [], []) do
            {:ok, %{rows: [[count]]}} ->
              {:ok, %{row_count: count}}

            {:error, reason} ->
              {:error, to_string(reason)}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      else
        {:error,
         "Table '#{if resolved_schema, do: "#{resolved_schema}.#{table_name}", else: table_name}' is not visible by Lotus policy"}
      end
    end)
  end

  @doc """
  Lists all relations (tables with schema information) in the given repository.

  Similar to list_tables/2 but returns {schema, table} tuples instead of just table names.
  Useful for UIs that need to display schema information.

  ## Examples

      {:ok, relations} = Lotus.Schema.list_relations("postgres", search_path: "reporting, public")
      # Returns [{"reporting", "customers"}, {"reporting", "orders"}, {"public", "users"}, ...]
  """
  @spec list_relations(module() | String.t(), keyword()) ::
          {:ok, [{String.t() | nil, String.t()}]} | {:error, term()}
  def list_relations(repo_or_name, opts \\ []) do
    adapter = Sources.resolve!(repo_or_name, nil)
    context = Keyword.get(opts, :context)
    start_time = Telemetry.schema_introspection_start(:list_relations, adapter.name)
    schemas = effective_schemas(adapter, opts)
    include_views? = Keyword.get(opts, :include_views, false)

    search_path = Keyword.get(opts, :search_path)

    key =
      schema_key(
        :list_relations,
        adapter.name,
        search_path || Enum.join(schemas, ","),
        include_views?
      )

    tags = ["repo:#{adapter.name}", "schema:list_relations"]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :schema)
      else
        :schema
      end

    result =
      exec_with_cache(opts[:cache], profile, key, tags, fn ->
        try do
          case Adapter.list_tables(adapter, schemas, include_views: include_views?) do
            {:ok, raw_relations} ->
              filtered =
                raw_relations
                |> Enum.filter(&Visibility.allowed_relation?(adapter.name, &1))

              run_after_discover(:after_list_relations, :relations, %{
                repo: adapter.name,
                repo_name: adapter.name,
                relations: filtered,
                context: context
              })

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    Telemetry.schema_introspection_stop(
      start_time,
      :list_relations,
      adapter.name,
      result_status(result)
    )

    result
  end

  defp run_after_discover(event, result_key, payload) do
    case Middleware.run(event, payload) do
      {:cont, updated} -> {:ok, Map.fetch!(updated, result_key)}
      {:halt, reason} -> {:error, reason}
    end
  end

  defp effective_schemas(adapter, opts) do
    schemas =
      cond do
        is_binary(Keyword.get(opts, :schema)) ->
          [Keyword.fetch!(opts, :schema)]

        is_list(Keyword.get(opts, :schemas)) ->
          Keyword.fetch!(opts, :schemas)

        is_binary(Keyword.get(opts, :search_path)) ->
          parse_search_path(Keyword.fetch!(opts, :search_path))

        true ->
          Adapter.default_schemas(adapter)
      end
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 == "$user"))

    if schemas == [], do: Adapter.default_schemas(adapter), else: schemas
  end

  defp parse_search_path(sp) when is_binary(sp),
    do: sp |> String.split(",") |> Enum.map(&String.trim/1)

  defp resolve_table_schema_with_cache(
         adapter,
         table,
         schemas,
         cache_opts,
         default_profile
       ) do
    search_key = Enum.join(schemas, ",")
    key = schema_key(:resolve_table_schema, adapter.name, search_key, table)
    tags = ["repo:#{adapter.name}", "schema:resolve_table_schema", "table:#{table}"]

    profile =
      if is_list(cache_opts),
        do: Keyword.get(cache_opts, :profile, default_profile),
        else: default_profile

    cache_result =
      exec_with_cache(cache_opts, profile, key, tags, fn ->
        case Adapter.resolve_table_schema(adapter, table, schemas) do
          {:ok, nil} -> {:ok, :not_found}
          {:ok, schema} -> {:ok, {:found, schema}}
          {:error, _} -> {:ok, :not_found}
        end
      end)

    case cache_result do
      {:ok, :not_found} -> nil
      {:ok, {:found, schema}} -> schema
      {:error, _} -> nil
    end
  end

  defp cache_mode(nil) do
    case Config.cache_adapter() do
      {:ok, _adapter} -> :use
      :error -> :off
    end
  end

  defp cache_mode(:bypass), do: :bypass
  defp cache_mode(:refresh), do: :refresh

  defp cache_mode(opts) when is_list(opts) do
    cond do
      :bypass in opts -> :bypass
      :refresh in opts -> :refresh
      true -> :use
    end
  end

  defp choose_ttl(cache_opts, default_profile) do
    get_explicit_ttl(cache_opts) || get_profile_ttl(cache_opts, default_profile)
  end

  defp get_explicit_ttl(cache_opts) when is_list(cache_opts) do
    Keyword.get(cache_opts, :ttl_ms)
  end

  defp get_explicit_ttl(_), do: nil

  defp get_profile_ttl(cache_opts, default_profile) do
    profile = determine_profile(cache_opts, default_profile)

    Config.cache_profile_settings(profile)[:ttl_ms] ||
      get_default_ttl() ||
      :timer.seconds(60)
  end

  defp determine_profile(cache_opts, default_profile) when is_list(cache_opts) do
    Keyword.get(cache_opts, :profile, default_profile || Config.default_cache_profile())
  end

  defp determine_profile(_cache_opts, nil), do: Config.default_cache_profile()
  defp determine_profile(_cache_opts, default_profile), do: default_profile

  defp get_default_ttl do
    case Config.cache_config() do
      nil -> nil
      config -> config[:default_ttl_ms]
    end
  end

  defp exec_with_cache(cache_opts, ttl_default_profile, key, tags, fun) do
    case cache_mode(cache_opts) do
      :off ->
        fun.()

      :bypass ->
        fun.()

      :refresh ->
        case fun.() do
          {:ok, val} ->
            ttl = choose_ttl(cache_opts, ttl_default_profile)
            :ok = Lotus.Cache.put(key, val, ttl, build_cache_options(cache_opts, tags))
            {:ok, val}

          other ->
            other
        end

      :use ->
        exec_with_cache_use(cache_opts, ttl_default_profile, key, tags, fun)
    end
  end

  defp exec_with_cache_use(cache_opts, ttl_default_profile, key, tags, fun) do
    ttl = choose_ttl(cache_opts, ttl_default_profile)
    opts = build_cache_options(cache_opts, tags)

    try do
      case Lotus.Cache.get_or_store(key, ttl, fn -> cache_value_or_throw(fun) end, opts) do
        {:ok, val, _meta} -> {:ok, val}
        {:error, _} -> fun.()
      end
    catch
      {:lotus_cache_error, e} -> {:error, e}
    end
  end

  defp cache_value_or_throw(fun) do
    case fun.() do
      {:ok, val} -> val
      {:error, e} -> throw({:lotus_cache_error, e})
    end
  end

  defp build_cache_options(cache_opts, tags) do
    base = [tags: tags]

    if is_list(cache_opts) do
      pass =
        cache_opts
        |> Enum.filter(fn
          {_k, _v} -> true
          _atom -> false
        end)
        |> Keyword.take([:max_bytes, :compress])

      Keyword.merge(pass, base)
    else
      base
    end
  end

  defp schema_key(:list_tables, repo_name, search_path, include_views) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({repo_name, search_path, include_views, Lotus.version()})
      )
      |> Base.encode16(case: :lower)

    "schema:list_tables:#{repo_name}:#{digest}"
  end

  defp schema_key(:list_relations, repo_name, search_path, include_views) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({repo_name, search_path, include_views, Lotus.version()})
      )
      |> Base.encode16(case: :lower)

    "schema:list_relations:#{repo_name}:#{digest}"
  end

  defp schema_key(:get_table_schema, repo_name, resolved_schema, table_name) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({repo_name, resolved_schema, table_name, Lotus.version()})
      )
      |> Base.encode16(case: :lower)

    "schema:get_table_schema:#{repo_name}:#{digest}"
  end

  defp schema_key(:get_table_stats, repo_name, resolved_schema, table_name) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({repo_name, resolved_schema, table_name, Lotus.version()})
      )
      |> Base.encode16(case: :lower)

    "schema:get_table_stats:#{repo_name}:#{digest}"
  end

  defp schema_key(:resolve_table_schema, repo_name, search_key, table) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({repo_name, search_key, table, Lotus.version()})
      )
      |> Base.encode16(case: :lower)

    "schema:resolve_table_schema:#{repo_name}:#{digest}"
  end

  defp schema_key(:list_schemas, repo_name) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({repo_name, Lotus.version()})
      )
      |> Base.encode16(case: :lower)

    "schema:list_schemas:#{repo_name}:#{digest}"
  end

  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, _}), do: :error
end
