defmodule Lotus.Schema do
  @moduledoc """
  Schema introspection functionality for Lotus.

  Provides functions to list tables and inspect table schemas across
  different database adapters (PostgreSQL, SQLite, etc.).
  """

  alias Lotus.{Visibility, Config, Source, Sources}

  @doc """
  Lists all schemas in the given PostgreSQL repository.

  Returns a list of schema names. For databases without schemas (like SQLite),
  returns an empty list.

  ## Options

  - `:cache` - Cache options (profile, ttl_ms, etc.)

  ## Examples

      {:ok, schemas} = Lotus.Schema.list_schemas(MyApp.Repo)
      # PostgreSQL: ["public", "reporting", ...]

      {:ok, schemas} = Lotus.Schema.list_schemas("postgres")
      # PostgreSQL: ["public", "reporting", ...]
  """
  @spec list_schemas(module() | String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def list_schemas(repo_or_name, opts \\ []) do
    {repo, repo_name} = Sources.resolve!(repo_or_name, nil)

    key = schema_key(:list_schemas, repo_name)
    tags = ["repo:#{repo_name}", "schema:list_schemas"]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :schema)
      else
        :schema
      end

    exec_with_cache(opts[:cache], profile, key, tags, fn ->
      try do
        {:ok, Source.list_schemas(repo)}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end)
  end

  @doc """
  Lists all tables in the given repository.

  For databases with schemas (like PostgreSQL), returns {schema, table} tuples.
  For databases without schemas (like SQLite), returns just table names as strings.

  ## Options

  - `:schema` - Search in specific schema (e.g., `schema: "reporting"`)
  - `:schemas` - Search in multiple schemas (e.g., `schemas: ["reporting", "public"]`)
  - `:search_path` - Use PostgreSQL search_path (e.g., `search_path: "reporting, public"`)
  - `:include_views` - Include views in results (default: false)

  ## Examples

      {:ok, tables} = Lotus.Schema.list_tables(MyApp.Repo)
      # PostgreSQL: [{"public", "users"}, {"public", "posts"}, ...]

      {:ok, tables} = Lotus.Schema.list_tables("postgres", search_path: "reporting, public")
      # PostgreSQL: [{"reporting", "customers"}, {"reporting", "orders"}, {"public", "users"}, ...]

      {:ok, tables} = Lotus.Schema.list_tables("sqlite")
      # SQLite: ["products", "orders", "order_items"]
  """
  @spec list_tables(module() | String.t(), keyword()) ::
          {:ok, [{String.t(), String.t()}] | [String.t()]} | {:error, term()}
  def list_tables(repo_or_name, opts \\ []) do
    {repo, repo_name} = Sources.resolve!(repo_or_name, nil)
    schemas = effective_schemas(repo, opts)
    include_views? = Keyword.get(opts, :include_views, false)

    search_path = Keyword.get(opts, :search_path)

    key =
      schema_key(:list_tables, repo_name, search_path || Enum.join(schemas, ","), include_views?)

    tags = ["repo:#{repo_name}", "schema:list_tables"]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :schema)
      else
        :schema
      end

    exec_with_cache(opts[:cache], profile, key, tags, fn ->
      try do
        raw_relations = Source.list_tables(repo, schemas, include_views?)

        filtered =
          raw_relations
          |> Enum.filter(&Visibility.allowed_relation?(repo_name, &1))

        result =
          if Enum.all?(filtered, fn {schema, _table} -> is_nil(schema) end) do
            # Schema-less database - return just table names
            Enum.map(filtered, fn {nil, table} -> table end)
          else
            # Schema-aware database - return {schema, table} tuples
            filtered
          end

        {:ok, result}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end)
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
    {repo, repo_name} = Sources.resolve!(repo_or_name, nil)
    schemas = effective_schemas(repo, opts)

    case resolve_table_schema_with_cache(
           repo,
           repo_name,
           table_name,
           schemas,
           opts[:cache],
           :schema
         ) do
      nil when schemas == [] ->
        # Schema-less database (SQLite) - nil is expected, proceed with nil schema
        get_table_schema_cached(repo, repo_name, table_name, nil, opts)

      nil ->
        {:error, "Table '#{table_name}' not found in schemas: #{Enum.join(schemas, ", ")}"}

      resolved_schema ->
        get_table_schema_cached(repo, repo_name, table_name, resolved_schema, opts)
    end
  end

  defp get_table_schema_cached(repo, repo_name, table_name, resolved_schema, opts) do
    key = schema_key(:get_table_schema, repo_name, resolved_schema, table_name)

    tags = [
      "repo:#{repo_name}",
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
      if Visibility.allowed_relation?(repo_name, {resolved_schema, table_name}) do
        try do
          {:ok, Source.get_table_schema(repo, resolved_schema, table_name)}
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
    {repo, repo_name} = Sources.resolve!(repo_or_name, nil)
    schemas = effective_schemas(repo, opts)

    case resolve_table_schema_with_cache(
           repo,
           repo_name,
           table_name,
           schemas,
           opts[:cache],
           :results
         ) do
      nil when schemas == [] ->
        # Schema-less database (SQLite) - nil is expected, proceed with nil schema
        get_table_stats_cached(repo, repo_name, table_name, nil, opts)

      nil ->
        {:error, "Table '#{table_name}' not found in schemas: #{Enum.join(schemas, ", ")}"}

      resolved_schema ->
        get_table_stats_cached(repo, repo_name, table_name, resolved_schema, opts)
    end
  end

  defp get_table_stats_cached(repo, repo_name, table_name, resolved_schema, opts) do
    key = schema_key(:get_table_stats, repo_name, resolved_schema, table_name)

    tags = [
      "repo:#{repo_name}",
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
      if Visibility.allowed_relation?(repo_name, {resolved_schema, table_name}) do
        try do
          count =
            if resolved_schema do
              {open_quote, close_quote} = get_quote_chars(repo)

              qt =
                "#{open_quote}#{String.replace(table_name, close_quote, close_quote <> close_quote)}#{close_quote}"

              qs =
                "#{open_quote}#{String.replace(resolved_schema, close_quote, close_quote <> close_quote)}#{close_quote}"

              %{rows: [[count]]} = repo.query!("SELECT COUNT(*) FROM #{qs}.#{qt}")
              count
            else
              # Schema-less database
              %{rows: [[count]]} = repo.query!("SELECT COUNT(*) FROM #{table_name}")
              count
            end

          {:ok, %{row_count: count}}
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
    {repo, repo_name} = Sources.resolve!(repo_or_name, nil)
    schemas = effective_schemas(repo, opts)
    include_views? = Keyword.get(opts, :include_views, false)

    search_path = Keyword.get(opts, :search_path)

    key =
      schema_key(
        :list_relations,
        repo_name,
        search_path || Enum.join(schemas, ","),
        include_views?
      )

    tags = ["repo:#{repo_name}", "schema:list_relations"]

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, :schema)
      else
        :schema
      end

    exec_with_cache(opts[:cache], profile, key, tags, fn ->
      try do
        raw_relations = Source.list_tables(repo, schemas, include_views?)

        {:ok,
         raw_relations
         |> Enum.filter(&Visibility.allowed_relation?(repo_name, &1))}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end)
  end

  defp effective_schemas(repo, opts) do
    schemas =
      cond do
        is_binary(Keyword.get(opts, :schema)) ->
          [Keyword.fetch!(opts, :schema)]

        is_list(Keyword.get(opts, :schemas)) ->
          Keyword.fetch!(opts, :schemas)

        is_binary(Keyword.get(opts, :search_path)) ->
          parse_search_path(Keyword.fetch!(opts, :search_path))

        sp = get_in(repo.config(), [:parameters, :search_path]) ->
          parse_search_path(sp)

        true ->
          Source.default_schemas(repo)
      end
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 == "$user"))

    if schemas == [], do: Source.default_schemas(repo), else: schemas
  end

  defp parse_search_path(sp) when is_binary(sp),
    do: sp |> String.split(",") |> Enum.map(&String.trim/1)

  defp resolve_table_schema_with_cache(
         repo,
         repo_name,
         table,
         schemas,
         cache_opts,
         default_profile
       ) do
    search_key = Enum.join(schemas, ",")
    key = schema_key(:resolve_table_schema, repo_name, search_key, table)
    tags = ["repo:#{repo_name}", "schema:resolve_table_schema", "table:#{table}"]

    profile =
      if is_list(cache_opts),
        do: Keyword.get(cache_opts, :profile, default_profile),
        else: default_profile

    case exec_with_cache(cache_opts, profile, key, tags, fn ->
           case Source.resolve_table_schema(repo, table, schemas) do
             nil -> {:ok, :not_found}
             schema -> {:ok, {:found, schema}}
           end
         end) do
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
    cond do
      is_list(cache_opts) and Keyword.has_key?(cache_opts, :ttl_ms) ->
        Keyword.fetch!(cache_opts, :ttl_ms)

      true ->
        prof =
          cond do
            is_list(cache_opts) and Keyword.has_key?(cache_opts, :profile) ->
              Keyword.fetch!(cache_opts, :profile)

            not is_nil(default_profile) ->
              default_profile

            true ->
              Config.default_cache_profile()
          end

        Config.cache_profile_settings(prof)[:ttl_ms] ||
          (Config.cache_config() && Config.cache_config()[:default_ttl_ms]) ||
          :timer.seconds(60)
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
        ttl = choose_ttl(cache_opts, ttl_default_profile)
        opts = build_cache_options(cache_opts, tags)

        try do
          case Lotus.Cache.get_or_store(
                 key,
                 ttl,
                 fn ->
                   case fun.() do
                     {:ok, val} -> val
                     {:error, e} -> throw({:lotus_cache_error, e})
                   end
                 end,
                 opts
               ) do
            {:ok, val, _meta} -> {:ok, val}
            {:error, _} -> fun.()
          end
        catch
          {:lotus_cache_error, e} -> {:error, e}
        end
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

  defp get_quote_chars(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.MyXQL -> {"`", "`"}
      Ecto.Adapters.Postgres -> {"\"", "\""}
      _ -> {"\"", "\""}
    end
  end
end
