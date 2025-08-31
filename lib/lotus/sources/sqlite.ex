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
end
