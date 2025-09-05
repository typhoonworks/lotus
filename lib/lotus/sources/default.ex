defmodule Lotus.Sources.Default do
  @moduledoc """
  Default source adapter implementation for unsupported or unknown database sources.

  Provides safe no-op implementations for source-specific functions and
  generic error formatting for database errors.
  """

  @behaviour Lotus.Source

  @impl true
  @doc "Simple transaction wrapper for unsupported sources."
  def execute_in_transaction(repo, fun, opts) do
    timeout = Keyword.get(opts, :timeout, 15_000)

    repo.transaction(fun, timeout: timeout)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  @doc "No-op: unsupported sources do not implement statement timeouts."
  def set_statement_timeout(_repo, _ms), do: :ok

  @impl true
  @doc "No-op: unsupported sources do not implement search_path."
  def set_search_path(_repo, _path), do: :ok

  @impl true
  @doc """
  Formats common error types into strings. Falls back to `inspect/1`
  for unknown values.
  """
  def format_error(%{__exception__: true} = e), do: Exception.message(e)
  def format_error(%DBConnection.EncodeError{message: msg}), do: msg
  def format_error(%ArgumentError{message: msg}), do: msg
  def format_error(msg) when is_binary(msg), do: msg
  def format_error(other), do: "Database Error: #{inspect(other)}"

  @impl true
  @doc """
  Returns a generic SQL parameter placeholder (`"?"`).

  This keeps the query builder working even for unknown sources,
  though actual binding semantics may differ.
  """
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  @doc """
  Returns generic placeholders for LIMIT and OFFSET (`"?"` for both).

  Unknown sources should implement their own version if they have specific requirements.
  """
  def limit_offset_placeholders(_limit_idx, _offset_idx) do
    {"?", "?"}
  end

  @impl true
  @doc "The default source does not handle any specific exceptions."
  def handled_errors, do: []

  @impl true
  @doc """
  Returns conservative deny rules covering common system tables from various databases.

  Since we don't know the specific source, we include deny rules for all known
  system tables to be safe.
  """
  def builtin_denies(_repo) do
    [
      {"pg_catalog", ~r/.*/},
      {"information_schema", ~r/.*/},
      {nil, ~r/^sqlite_/},
      {nil, "schema_migrations"},
      {"public", "schema_migrations"},
      {"public", "lotus_queries"},
      {nil, "lotus_queries"}
    ]
  end

  @impl true
  def default_schemas(_repo) do
    # Conservative default for unknown sources
    ["public"]
  end

  @impl true
  def builtin_schema_denies(_repo) do
    # Conservative denies covering common system schemas from various databases
    ["pg_catalog", "information_schema", "mysql", "performance_schema", "sys"]
  end

  @impl true
  @doc """
  Generic list_schemas implementation that returns an empty list.
  Unknown sources should implement their own version if they support schema introspection.
  """
  def list_schemas(_repo) do
    []
  end

  @impl true
  @doc """
  Generic list_tables implementation that returns an empty list.
  Unknown sources should implement their own version if they support schema introspection.
  """
  def list_tables(_repo, _schemas, _include_views?) do
    []
  end

  @impl true
  @doc """
  Generic get_table_schema implementation that returns an empty schema.
  Unknown sources should implement their own version if they support schema introspection.
  """
  def get_table_schema(_repo, _schema, _table) do
    []
  end

  @impl true
  @doc """
  Generic resolve_table_schema that always returns nil.
  This is appropriate for databases without schema support or unknown sources.
  """
  def resolve_table_schema(_repo, _table, _schemas) do
    nil
  end
end
