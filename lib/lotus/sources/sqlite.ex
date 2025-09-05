defmodule Lotus.Sources.SQLite3 do
  @moduledoc false

  @behaviour Lotus.Source

  require Logger

  @exlite_error Module.concat([:Exqlite, :Error])

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    read_only? = Keyword.get(opts, :read_only, true)
    timeout = Keyword.get(opts, :timeout, 15_000)

    # Snapshot whether PRAGMA is supported and the previous value
    {pragma_supported?, prev_state} =
      if read_only? do
        try do
          case repo.query("PRAGMA query_only") do
            {:ok, %{rows: [[prev]]}} ->
              repo.query!("PRAGMA query_only = ON")
              {true, prev}

            _ ->
              {false, nil}
          end
        rescue
          error in [Exqlite.Error] ->
            msg = error.message || Exception.message(error)

            if msg =~ "no such pragma" or msg =~ "unknown pragma" do
              Logger.warning("""
              SQLite version does not support PRAGMA query_only.
              Consider opening the DB in read-only mode
              (e.g., database=...&mode=ro or database=...&immutable=1).
              """)

              {false, nil}
            else
              reraise error, __STACKTRACE__
            end
        end
      else
        {false, nil}
      end

    try do
      repo.transaction(fun, timeout: timeout)
    after
      if pragma_supported? do
        try do
          restore = if prev_state in [0, 1], do: prev_state, else: 0
          repo.query!("PRAGMA query_only = #{restore}")
        rescue
          _ -> :ok
        end
      end
    end
  end

  @impl true
  def set_statement_timeout(_repo, _timeout_ms), do: :ok

  @impl true
  def set_search_path(_repo, _search_path), do: :ok

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @exlite_error do
    "SQLite Error: " <> (Map.get(e, :message) || Exception.message(e))
  end

  def format_error(other), do: Lotus.Sources.Default.format_error(other)

  @impl true
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  def limit_offset_placeholders(_limit_idx, _offset_idx) do
    # SQLite uses simple ? placeholders for LIMIT/OFFSET
    {"?", "?"}
  end

  @impl true
  def handled_errors, do: [Exqlite.Error]

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"

    [
      {nil, ~r/^sqlite_/},
      {nil, ms},
      {nil, "lotus_queries"}
    ]
  end

  @impl true
  def default_schemas(_repo) do
    # SQLite is schema-less
    []
  end

  @impl true
  def builtin_schema_denies(_repo) do
    # SQLite doesn't have schemas
    []
  end

  @impl true
  def list_schemas(_repo) do
    # SQLite doesn't have schemas
    []
  end

  @impl true
  def list_tables(repo, _schemas, _include_views?) do
    # SQLite doesn't have schemas, so we ignore the schemas parameter
    query = """
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name NOT LIKE 'sqlite_%'
    ORDER BY name
    """

    result = repo.query!(query)
    # Return consistent format: {nil, table_name} for SQLite
    Enum.map(result.rows, fn [table_name] -> {nil, table_name} end)
  end

  @impl true
  def get_table_schema(repo, _schema, table_name) do
    # SQLite doesn't use schemas, ignore the schema parameter
    query = "PRAGMA table_info(#{table_name})"

    result = repo.query!(query)

    Enum.map(result.rows, fn row ->
      [_cid, name, type, notnull, default, pk] = row

      %{
        name: name,
        type: type,
        nullable: notnull == 0,
        default: default,
        primary_key: pk == 1
      }
    end)
  end

  @impl true
  def resolve_table_schema(_repo, _table, _schemas) do
    # SQLite doesn't have schemas, always return nil
    nil
  end
end
