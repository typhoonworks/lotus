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

      # Create and save a query
      {:ok, query} = Lotus.create_query(%{
        name: "Active Users",
        query: %{sql: "SELECT * FROM users WHERE active = true"}
      })

      # Execute a saved query
      {:ok, results} = Lotus.run_query(query)

      # Execute SQL directly (read-only)
      {:ok, results} = Lotus.run_sql("SELECT * FROM products WHERE price > $1", [100])
  """

  alias Lotus.{Config, Storage, Runner, QueryResult}
  alias Lotus.Storage.Query

  @type opts :: [
          timeout: non_neg_integer(),
          statement_timeout_ms: non_neg_integer(),
          read_only: boolean(),
          prefix: binary()
        ]

  @doc """
  Returns the configured Ecto repository.
  """
  def repo, do: Config.repo!()

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
      Lotus.run_query(query_id, prefix: "analytics")

  """
  @spec run_query(Query.t() | term(), opts()) :: {:ok, QueryResult.t()} | {:error, term()}
  def run_query(query_or_id, opts \\ [])

  def run_query(%Query{} = q, opts) do
    {sql, params} = Query.to_sql_params(q)
    Runner.run_sql(repo(), sql, params, opts)
  end

  def run_query(id, opts) do
    q = Storage.get_query!(id)
    run_query(q, opts)
  end

  @doc """
  Run ad-hoc SQL (bypassing storage), still read-only and sandboxed.
  """
  @spec run_sql(binary(), list(any()), opts()) :: {:ok, QueryResult.t()} | {:error, term()}
  def run_sql(sql, params \\ [], opts \\ []) do
    Runner.run_sql(repo(), sql, params, opts)
  end

  @doc """
  Returns the configured primary key type (:id or :binary_id).
  """
  defdelegate primary_key_type(), to: Config

  @doc """
  Returns the configured foreign key type (:id or :binary_id).
  """
  defdelegate foreign_key_type(), to: Config

  @doc """
  Returns whether unique query names are enforced.
  """
  defdelegate unique_names?(), to: Config
end
