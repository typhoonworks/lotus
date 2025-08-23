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

      # Create and save a query with smart variables
      {:ok, query} = Lotus.create_query(%{
        name: "Active Users",
        statement: "SELECT * FROM users WHERE active = {is_active}",
        var_defaults: %{"is_active" => true},
        search_path: "reporting, public"
      })

      # Execute a saved query
      {:ok, results} = Lotus.run_query(query)

      # Execute SQL directly (read-only)
      {:ok, results} = Lotus.run_sql("SELECT * FROM products WHERE price > $1", [100])
  """

  alias Lotus.{Config, Storage, Runner, QueryResult, Schema}
  alias Lotus.Storage.Query

  @type opts :: [
          timeout: non_neg_integer(),
          statement_timeout_ms: non_neg_integer(),
          read_only: boolean(),
          search_path: binary() | nil
        ]

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
  Lists all saved queries.
  """
  defdelegate list_queries(), to: Storage

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

  ## Examples

      Lotus.run_query(query)
      Lotus.run_query(query, timeout: 10_000)
      Lotus.run_query(query_id)
      Lotus.run_query(query_id, repo: MyApp.DataRepo)

  """
  @spec run_query(Query.t() | term(), opts()) :: {:ok, QueryResult.t()} | {:error, term()}
  def run_query(query_or_id, opts \\ [])

  def run_query(%Query{} = q, opts) do
    vars = Keyword.get(opts, :vars, %{})

    {sql, params} =
      try do
        Query.to_sql_params(q, vars)
      rescue
        ArgumentError ->
          {:error, "Missing required variable"}
      end

    case {sql, params} do
      {:error, msg} ->
        {:error, msg}

      {sql, params} ->
        repo_from_opts = Keyword.get(opts, :repo)
        repo_from_query = q.data_repo

        search_path_from_opts = Keyword.get(opts, :search_path)
        search_path = search_path_from_opts || q.search_path

        final_opts =
          if search_path do
            Keyword.put(opts, :search_path, search_path)
          else
            opts
          end

        execution_repo = resolve_execution_repo(repo_from_opts || repo_from_query)
        Runner.run_sql(execution_repo, sql, params, final_opts)
    end
  end

  def run_query(id, opts) do
    q = Storage.get_query!(id)
    run_query(q, opts)
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
  """
  @spec run_sql(binary(), list(any()), [
          {:read_only, boolean()}
          | {:statement_timeout_ms, non_neg_integer()}
          | {:timeout, non_neg_integer()}
          | {:search_path, binary() | nil}
        ]) ::
          {:ok, QueryResult.t()} | {:error, term()}
  def run_sql(sql, params \\ [], opts \\ []) do
    execution_repo = resolve_execution_repo(Keyword.get(opts, :repo))
    Runner.run_sql(execution_repo, sql, params, opts)
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

  # Private helper to resolve execution repo from various inputs
  defp resolve_execution_repo(nil) do
    # Default behavior: use first configured data repo, or storage repo if none
    case list_data_repo_names() do
      [] -> repo()
      [first_name | _] -> get_data_repo!(first_name)
    end
  end

  defp resolve_execution_repo(repo_name) when is_binary(repo_name) do
    get_data_repo!(repo_name)
  end

  defp resolve_execution_repo(repo_module) when is_atom(repo_module) do
    repo_module
  end
end
