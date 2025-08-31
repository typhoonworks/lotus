defmodule Lotus.Source do
  @moduledoc """
  Source behavior for database-specific operations.

  Defines the interface that each database source adapter's operations module must implement.
  """

  @type repo :: Ecto.Repo.t()

  @callback execute_in_transaction(repo, (-> any()), keyword()) :: {:ok, any()} | {:error, any()}
  @callback set_statement_timeout(repo, non_neg_integer()) :: :ok | no_return()
  @callback set_search_path(repo, String.t()) :: :ok | no_return()
  @callback format_error(any()) :: String.t()

  @doc """
  Return the list of built-in deny rules for system tables and metadata relations
  that should be hidden from the schema browser for this source.

  Each rule is a `{schema_pattern, table_pattern}` tuple where patterns can be
  exact strings or regexes. Example rules:

    * `{"pg_catalog", ~r/.*/}` → deny all tables in Postgres `pg_catalog`
    * `{nil, ~r/^sqlite_/}`   → deny all tables starting with `sqlite_` in SQLite
    * `{"public", "schema_migrations"}` → deny migrations table in Postgres
  """
  @callback builtin_denies(repo) ::
              [{String.t() | nil | Regex.t(), String.t() | Regex.t()}]

  @doc """
  Return the SQL parameter placeholder string for a variable at a given index.

  The placeholder may include database-specific type casting based on the variable type.

  Examples of source-specific output:
    * Postgres → `"$1"` (untyped), `"$1::integer"` (typed)
    * MySQL    → `"?"` (untyped), `"CAST(? AS SIGNED)"` (typed)
    * SQLite   → `"?"` (always untyped)

  Supported types for casting: `:date`, `:datetime`, `:time`, `:number`, `:integer`, `:boolean`, `:json`
  """
  @callback param_placeholder(index :: pos_integer(), var :: String.t(), type :: atom() | nil) ::
              String.t()

  @doc """
  List the exception modules that this source formats specially in `format_error/1`.
  """
  @callback handled_errors() :: [module()]

  @impls %{
    Ecto.Adapters.Postgres => Lotus.Sources.Postgres,
    Ecto.Adapters.SQLite3 => Lotus.Sources.SQLite3,
    Ecto.Adapters.MyXQL => Lotus.Sources.MySQL
  }

  @doc """
  Executes a function within a transaction with source-specific session management.

  The source handles:
  - Starting a transaction with appropriate timeout
  - Setting read-only mode, statement timeout, and search path if specified in opts
  - Running the provided function
  - Properly cleaning up session state (important for MySQL/SQLite session persistence)

  Options:
  - `:read_only` - whether to run in read-only mode (default: true)
  - `:statement_timeout_ms` - statement timeout in milliseconds (default: 5000)
  - `:timeout` - transaction timeout in milliseconds (default: 15000)
  - `:search_path` - PostgreSQL search path (optional)
  """
  @spec execute_in_transaction(repo, (-> any()), keyword()) :: {:ok, any()} | {:error, any()}
  def execute_in_transaction(repo, fun, opts \\ []) do
    impl_for(repo).execute_in_transaction(repo, fun, opts)
  end

  @doc """
  Sets the **statement timeout** (in milliseconds) for the given repository,
  if supported by the underlying source.
  """
  @spec set_statement_timeout(repo, non_neg_integer()) :: :ok | no_return()
  def set_statement_timeout(repo, ms), do: impl_for(repo).set_statement_timeout(repo, ms)

  @doc """
  Sets the **search path** (schema list) for the given repository,
  if supported by the underlying source.

  On unsupported sources this is a no-op.
  """
  @spec set_search_path(repo, String.t()) :: :ok | no_return()
  def set_search_path(repo, path) when is_binary(path),
    do: impl_for(repo).set_search_path(repo, path)

  def set_search_path(_, _), do: :ok

  @doc """
  Returns the list of built-in deny rules for system tables and metadata relations.

  These rules are used by the visibility module to filter out system tables.
  """
  @spec builtin_denies(repo) :: [{String.t() | nil | Regex.t(), String.t() | Regex.t()}]
  def builtin_denies(repo), do: impl_for(repo).builtin_denies(repo)

  @doc """
  Formats a database error into a consistent, human-readable string.

  Dispatches to the correct source if the error type is recognized,
  otherwise falls back to the default implementation.
  """
  @spec format_error(any()) :: String.t()
  def format_error(error), do: impl_for_error(error).format_error(error)

  @doc """
  Returns the source-specific **SQL parameter placeholder** to substitute
  for `{{var}}` occurrences.

  - `repo_or_name` can be the Repo module or a data-repo name string.
  - `index` is 1-based (for drivers like Postgres that need `$1`, `$2`, …).
  - `var` and `type` are available to sources if they need special handling.

  If the repo cannot be resolved, we default to Postgres-style placeholders.
  """
  @spec param_placeholder(repo | String.t() | nil, pos_integer(), String.t(), atom() | nil) ::
          String.t()
  def param_placeholder(repo_or_name, index, var, type) when is_integer(index) and index > 0 do
    case resolve_repo(repo_or_name) do
      nil -> Lotus.Sources.Postgres.param_placeholder(index, var, type)
      repo -> impl_for(repo).param_placeholder(index, var, type)
    end
  end

  defp resolve_repo(nil), do: nil
  defp resolve_repo(repo) when is_atom(repo), do: repo

  defp resolve_repo(repo_name) when is_binary(repo_name) do
    Lotus.Config.get_data_repo!(repo_name)
  end

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
end
