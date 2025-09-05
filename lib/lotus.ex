defmodule Lotus do
  @moduledoc """
  Lotus is a lightweight Elixir library for saving and executing read-only SQL queries.

  This module provides the main public API, orchestrating between:
  - Storage: Query persistence and management
  - Runner: SQL execution with safety checks
  - Migrations: Database schema management

  ## Configuration

  Add to your config:

      config :lotus,
        repo: MyApp.Repo,
        primary_key_type: :id,    # or :binary_id
        foreign_key_type: :id     # or :binary_id

  ## Usage

      # Create and save a query with variables
      {:ok, query} = Lotus.create_query(%{
        name: "Active Users",
        statement: "SELECT * FROM users WHERE active = {{is_active}}",
        variables: [
          %{name: "is_active", type: :text, label: "Is Active", default: "true"}
        ],
        search_path: "reporting, public"
      })

      # Execute a saved query
      {:ok, results} = Lotus.run_query(query)

      # Execute SQL directly (read-only)
      {:ok, results} = Lotus.run_sql("SELECT * FROM products WHERE price > $1", [100])
  """

  @default_page_size 1000

  @type cache_opt ::
          :bypass
          | :refresh
          | {:ttl_ms, non_neg_integer()}
          | {:profile, atom()}
          | {:tags, [binary()]}

  @type window_count_mode :: :none | :exact

  @type window_opts :: [
          limit: pos_integer(),
          offset: non_neg_integer(),
          count: window_count_mode
        ]

  @type opts :: [
          timeout: non_neg_integer(),
          statement_timeout_ms: non_neg_integer(),
          read_only: boolean(),
          search_path: binary() | nil,
          repo: binary() | nil,
          vars: map(),
          cache: [cache_opt] | :bypass | :refresh | nil,
          window: window_opts
        ]

  alias Lotus.{Config, Storage, Runner, Result, Schema, Sources}
  alias Lotus.Storage.Query

  def child_spec(opts), do: Lotus.Supervisor.child_spec(opts)
  def start_link(opts \\ []), do: Lotus.Supervisor.start_link(opts)

  @doc """
  Returns the current version of Lotus.
  """
  def version do
    Application.spec(:lotus, :vsn)
    |> to_string()
  end

  @doc """
  Returns the configured Ecto repository where Lotus stores query definitions.
  """
  def repo, do: Config.repo!()

  @doc """
  Returns all configured data repositories.
  """
  def data_repos, do: Config.data_repos()

  @doc """
  Gets a data repository by name.

  Raises if the repository is not configured.
  """
  def get_data_repo!(name), do: Config.get_data_repo!(name)

  @doc """
  Lists the names of all configured data repositories.

  Useful for building UI dropdowns.
  """
  def list_data_repo_names, do: Config.list_data_repo_names()

  @doc """
  Returns the default data repository as a {name, module} tuple.

  - If there's only one data repo configured, returns it
  - If multiple repos are configured and default_repo is set, returns that repo
  - If multiple repos are configured without default_repo, raises an error
  - If no data repos are configured, raises an error
  """
  def default_data_repo, do: Config.default_data_repo()

  @doc """
  Lists all saved queries.
  """
  defdelegate list_queries(), to: Storage

  @doc """
  Gets a single query by ID. Returns nil if not found.
  """
  defdelegate get_query(id), to: Storage

  @doc """
  Gets a single query by ID. Raises if not found.
  """
  defdelegate get_query!(id), to: Storage

  @doc """
  Creates a new saved query.
  """
  defdelegate create_query(attrs), to: Storage

  @doc """
  Updates an existing query.
  """
  defdelegate update_query(query, attrs), to: Storage

  @doc """
  Deletes a saved query.
  """
  defdelegate delete_query(query), to: Storage

  @doc """
  Run a saved query (by struct or id).

  Variables in the query statement (using `{{variable_name}}` syntax) are
  substituted with values from the query's default variables and any runtime
  overrides provided via the `vars` option.

  ## Variable Resolution

  Variables are resolved in this order:
  1. Runtime values from `vars` option (highest priority)
  2. Default values from the query's variable definitions
  3. If neither exists, raises an error for missing required variable

  ## Examples

      # Run query with default variable values
      Lotus.run_query(query)

      # Override variables at runtime
      Lotus.run_query(query, vars: %{"min_age" => 25, "status" => "active"})

      # Run with timeout and repo options
      Lotus.run_query(query, timeout: 10_000, repo: MyApp.DataRepo)

      # Run by query ID
      Lotus.run_query(query_id, vars: %{"user_id" => 123})

  ## Variable Types

  Variables are automatically cast based on their type definition:
  - `:text` - Used as-is (strings)
  - `:number` - Cast from string to integer
  - `:date` - Cast from ISO8601 string to Date struct


  ### Windowed pagination
  Pass `window: [limit: pos_integer, offset: non_neg_integer, count: :none | :exact]` to
  return only a page of rows from the original query. When `count: :exact`, Lotus will
  also compute `SELECT COUNT(*) FROM (original_sql)` and include `meta.total_count` in
  the result. The `num_rows` field always reflects the number of rows in the returned page.
  """
  @spec run_query(Query.t() | term(), opts()) :: {:ok, Result.t()} | {:error, term()}
  def run_query(query_or_id, opts \\ [])

  def run_query(%Query{} = q, opts) do
    supplied_vars = Keyword.get(opts, :vars, %{}) || %{}

    defaults =
      q.variables
      |> Enum.filter(& &1.default)
      |> Map.new(fn v -> {v.name, v.default} end)

    vars = Map.merge(defaults, supplied_vars)

    {sql, params} =
      try do
        Query.to_sql_params(q, vars)
      rescue
        e in ArgumentError ->
          {:error, e.message}
      end

    case {sql, params} do
      {:error, msg} ->
        {:error, msg}

      {sql, params} ->
        {repo_mod, repo_name} = Sources.resolve!(Keyword.get(opts, :repo), q.data_repo)

        search_path = Keyword.get(opts, :search_path) || q.search_path
        final_opts = if search_path, do: Keyword.put(opts, :search_path, search_path), else: opts

        {sql, params, window_meta, cache_bound} =
          maybe_apply_window(
            sql,
            params,
            repo_mod || repo_name,
            search_path,
            Keyword.get(opts, :window)
          )

        key = result_key(sql, cache_bound || vars, repo_name, search_path)

        tags =
          ["query:#{q.id}", "repo:#{repo_name}"] ++
            if is_list(opts[:cache]), do: Keyword.get(opts[:cache], :tags, []), else: []

        profile =
          if is_list(opts[:cache]) do
            Keyword.get(opts[:cache], :profile, Config.default_cache_profile())
          else
            Config.default_cache_profile()
          end

        exec_with_cache(opts[:cache], profile, key, tags, fn ->
          with {:ok, %Result{} = res} <- Runner.run_sql(repo_mod, sql, params, final_opts) do
            {:ok, merge_window_meta(res, window_meta)}
          end
        end)
    end
  end

  def run_query(id, opts) do
    q = Storage.get_query!(id)
    run_query(q, opts)
  end

  @doc """
  Checks if a query can be run with the provided variables.

  Returns true if all required variables have values (either from defaults
  or supplied vars), false otherwise.

  ## Examples

      # Query with all required variables having defaults
      Lotus.can_run?(query)
      # => true

      # Query missing required variables
      Lotus.can_run?(query)
      # => false

      # Query with runtime variable overrides
      Lotus.can_run?(query, vars: %{"user_id" => 123})
      # => true (if user_id was the missing variable)

  """
  @spec can_run?(Query.t()) :: boolean()
  @spec can_run?(Query.t(), opts()) :: boolean()
  def can_run?(query, opts \\ [])

  def can_run?(%Query{} = q, opts) do
    supplied_vars = Keyword.get(opts, :vars, %{}) || %{}

    defaults =
      q.variables
      |> Enum.filter(& &1.default)
      |> Map.new(fn v -> {v.name, v.default} end)

    vars = Map.merge(defaults, supplied_vars)

    try do
      Query.to_sql_params(q, vars)
      true
    rescue
      ArgumentError ->
        false
    end
  end

  @doc """
  Run ad-hoc SQL (bypassing storage), still read-only and sandboxed.

  ## Examples

      # Run against default configured repo
      {:ok, result} = Lotus.run_sql("SELECT * FROM users")

      # Run against specific repo
      {:ok, result} = Lotus.run_sql("SELECT * FROM products", [], repo: MyApp.DataRepo)

      # With parameters
      {:ok, result} = Lotus.run_sql("SELECT * FROM users WHERE id = $1", [123])

      # With search_path for schema resolution
      {:ok, result} = Lotus.run_sql("SELECT * FROM users", [], search_path: "reporting, public")

  ### Windowed pagination
  Pass `window: [limit: pos_integer, offset: non_neg_integer, count: :none | :exact]` to
  page results from the SQL. See `run_query/2` for details. The cache key automatically
  incorporates the window so different pages are cached independently.
  """
  @spec run_sql(binary(), list(any()), [
          {:read_only, boolean()}
          | {:statement_timeout_ms, non_neg_integer()}
          | {:timeout, non_neg_integer()}
          | {:search_path, binary() | nil}
          | {:repo, atom() | binary()}
          | {:window, window_opts}
        ]) ::
          {:ok, Result.t()} | {:error, term()}
  def run_sql(sql, params \\ [], opts \\ []) do
    {repo_mod, repo_name} = Sources.resolve!(Keyword.get(opts, :repo), nil)
    runner_opts = Keyword.delete(opts, :repo)
    search_path = Keyword.get(runner_opts, :search_path)

    {sql, params, window_meta, cache_bound} =
      maybe_apply_window(
        sql,
        params,
        repo_mod || repo_name,
        search_path,
        Keyword.get(opts, :window)
      )

    key = result_key(sql, cache_bound || params, repo_name, search_path)

    tags =
      ["repo:#{repo_name}"] ++
        if is_list(opts[:cache]), do: Keyword.get(opts[:cache], :tags, []), else: []

    profile =
      if is_list(opts[:cache]) do
        Keyword.get(opts[:cache], :profile, Config.default_cache_profile())
      else
        Config.default_cache_profile()
      end

    exec_with_cache(opts[:cache], profile, key, tags, fn ->
      with {:ok, %Result{} = res} <- Runner.run_sql(repo_mod, sql, params, runner_opts) do
        {:ok, merge_window_meta(res, window_meta)}
      end
    end)
  end

  @doc """
  Returns whether unique query names are enforced.
  """
  defdelegate unique_names?(), to: Config

  @doc """
  Lists all tables in a data repository.

  For databases with schemas (PostgreSQL), returns {schema, table} tuples.
  For databases without schemas (SQLite), returns just table names as strings.

  ## Examples

      {:ok, tables} = Lotus.list_tables("postgres")
      # Returns [{"public", "users"}, {"public", "posts"}, ...]

      {:ok, tables} = Lotus.list_tables("postgres", search_path: "reporting, public")
      # Returns [{"reporting", "customers"}, {"public", "users"}, ...]

      {:ok, tables} = Lotus.list_tables("sqlite")
      # Returns ["products", "orders", "order_items"]
  """
  def list_tables(repo_or_name, opts \\ []), do: Schema.list_tables(repo_or_name, opts)

  @doc """
  Lists all schemas in the given repository.

  Returns a list of schema names. For databases without schemas (like SQLite),
  returns an empty list.

  ## Examples

      {:ok, schemas} = Lotus.list_schemas("postgres")
      # Returns ["public", "reporting", ...]

      {:ok, schemas} = Lotus.list_schemas("sqlite")
      # Returns []
  """
  def list_schemas(repo_or_name, opts \\ []), do: Schema.list_schemas(repo_or_name, opts)

  @doc """
  Gets the schema for a specific table.

  ## Examples

      {:ok, schema} = Lotus.get_table_schema("primary", "users")
      {:ok, schema} = Lotus.get_table_schema("postgres", "customers", schema: "reporting")
      {:ok, schema} = Lotus.get_table_schema(MyApp.DataRepo, "products", search_path: "analytics, public")
  """
  def get_table_schema(repo_or_name, table_name, opts \\ []),
    do: Schema.get_table_schema(repo_or_name, table_name, opts)

  @doc """
  Gets statistics for a specific table.

  ## Examples

      {:ok, stats} = Lotus.get_table_stats("primary", "users")
      {:ok, stats} = Lotus.get_table_stats("postgres", "customers", schema: "reporting")
      # Returns %{row_count: 1234}
  """
  def get_table_stats(repo_or_name, table_name, opts \\ []),
    do: Schema.get_table_stats(repo_or_name, table_name, opts)

  @doc """
  Lists all relations (tables with schema information) in a data repository.

  ## Examples

      {:ok, relations} = Lotus.list_relations("postgres", search_path: "reporting, public")
      # Returns [{"reporting", "customers"}, {"public", "users"}, ...]
  """
  def list_relations(repo_or_name, opts \\ []), do: Schema.list_relations(repo_or_name, opts)

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
      # caller explicitly passed a ttl override
      is_list(cache_opts) and Keyword.has_key?(cache_opts, :ttl_ms) ->
        Keyword.fetch!(cache_opts, :ttl_ms)

      true ->
        # resolve profile in this order:
        # 1. caller passed `:profile`
        # 2. fallback from caller (e.g. :results / :schema)
        # 3. globally configured default profile
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
            cache_options = build_cache_options(cache_opts, tags)
            :ok = Lotus.Cache.put(key, val, ttl, cache_options)
            {:ok, val}

          error ->
            error
        end

      :use ->
        ttl = choose_ttl(cache_opts, ttl_default_profile)

        try do
          cache_options = build_cache_options(cache_opts, tags)

          case Lotus.Cache.get_or_store(
                 key,
                 ttl,
                 fn ->
                   case fun.() do
                     {:ok, val} -> val
                     {:error, e} -> throw({:lotus_cache_error, e})
                   end
                 end,
                 cache_options
               ) do
            {:ok, val, _} -> {:ok, val}
            {:error, _} -> fun.()
          end
        catch
          {:lotus_cache_error, e} -> {:error, e}
        end
    end
  end

  defp build_cache_options(cache_opts, tags) do
    base_options = [tags: tags]

    if is_list(cache_opts) do
      cache_options =
        cache_opts
        |> Enum.filter(fn
          {_key, _value} -> true
          _atom -> false
        end)
        |> Keyword.take([:max_bytes, :compress])

      Keyword.merge(cache_options, base_options)
    else
      base_options
    end
  end

  defp result_key(sql, bound_vars_map, repo_name, search_path) do
    Lotus.Cache.Key.result(sql, bound_vars_map,
      data_repo: repo_name,
      search_path: search_path,
      lotus_version: Lotus.version()
    )
  end

  defp resolve_window_limit(window_opts) do
    max_limit = Config.default_page_size() || @default_page_size

    case Keyword.get(window_opts, :limit) do
      nil ->
        max_limit

      limit when not is_integer(limit) or limit <= 0 ->
        max_limit

      limit ->
        min(limit, max_limit)
    end
  end

  defp maybe_apply_window(sql, params, _repo_or_name, _search_path, nil),
    do: {sql, params, nil, nil}

  defp maybe_apply_window(sql, params, repo_or_name, search_path, window_opts)
       when is_list(window_opts) do
    base_sql = trim_trailing_semicolon(sql)
    limit = resolve_window_limit(window_opts)
    offset = Keyword.get(window_opts, :offset, 0)
    count_mode = Keyword.get(window_opts, :count, :none)

    {limit_ph, offset_ph} =
      Lotus.Source.limit_offset_placeholders(
        repo_or_name,
        length(params) + 1,
        length(params) + 2
      )

    paged_sql =
      "SELECT * FROM (" <>
        base_sql <> ") AS lotus_sub LIMIT " <> limit_ph <> " OFFSET " <> offset_ph

    paged_params = params ++ [limit, offset]

    window_meta =
      case count_mode do
        :exact ->
          %{
            window: %{limit: limit, offset: offset},
            total_count: :pending,
            total_mode: :exact,
            count_sql: "SELECT COUNT(*) FROM (" <> base_sql <> ") AS lotus_sub",
            count_params: params,
            repo_or_name: repo_or_name,
            search_path: search_path
          }

        _ ->
          %{window: %{limit: limit, offset: offset}, total_count: nil, total_mode: :none}
      end

    # Include window in cache key bound variables
    cache_bound = %{
      __params__: params,
      __window__: %{limit: limit, offset: offset, count: count_mode}
    }

    {paged_sql, paged_params, window_meta, cache_bound}
  end

  defp merge_window_meta(%Result{} = res, nil), do: res

  defp merge_window_meta(%Result{} = res, %{total_mode: :none, window: win} = _meta) do
    updated_meta = Map.merge(res.meta, %{window: win})
    %Result{res | num_rows: length(res.rows), meta: updated_meta}
  end

  defp merge_window_meta(%Result{} = res, %{total_mode: :exact} = meta) do
    win = Map.fetch!(meta, :window)

    # Try to compute exact count synchronously. If it fails, fall back with no total.
    total_count =
      case do_count(meta) do
        {:ok, n} when is_integer(n) and n >= 0 -> n
        _ -> nil
      end

    updated_meta =
      Map.merge(res.meta, %{window: win, total_count: total_count, total_mode: :exact})

    %Result{
      res
      | num_rows: length(res.rows),
        meta: updated_meta
    }
  end

  defp do_count(
         %{count_sql: count_sql, count_params: count_params, repo_or_name: repo_or_name} = meta
       ) do
    {repo_mod, _repo_name} = Sources.resolve!(repo_or_name, nil)

    runner_opts = []

    runner_opts =
      case Map.get(meta, :search_path) do
        sp when is_binary(sp) and byte_size(sp) > 0 -> Keyword.put(runner_opts, :search_path, sp)
        _ -> runner_opts
      end

    case Runner.run_sql(repo_mod, count_sql, count_params, runner_opts) do
      {:ok, %Result{rows: [[n]]}} when is_integer(n) ->
        {:ok, n}

      {:ok, %Result{rows: [[n]]}} when is_binary(n) ->
        case Integer.parse(n) do
          {v, _} -> {:ok, v}
          _ -> {:error, :invalid_count}
        end

      {:ok, %Result{rows: _}} ->
        {:error, :invalid_count}

      other ->
        other
    end
  end

  defp trim_trailing_semicolon(sql) do
    s = String.trim(sql)

    if String.ends_with?(s, ";") do
      s
      |> String.trim_trailing()
      |> String.trim_trailing(";")
      |> String.trim_trailing()
    else
      s
    end
  end
end
