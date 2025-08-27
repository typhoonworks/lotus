defmodule Lotus.Adapter.SQLite3 do
  @moduledoc false

  @behaviour Lotus.Adapter
  require Logger

  @impl true
  def set_read_only(repo) do
    try do
      repo.query!("PRAGMA query_only = ON")
      :ok
    rescue
      error in [Exqlite.Error] ->
        msg = error.message || Exception.message(error)

        if msg =~ "no such pragma" or msg =~ "unknown pragma" do
          Logger.warning("""
          SQLite version does not support PRAGMA query_only.
          Consider opening the connection in read-only mode instead
          (database=...&mode=ro or database=...&immutable=1).
          """)

          :ok
        else
          reraise error, __STACKTRACE__
        end
    end
  end

  @impl true
  # No-op: SQLite does not support statement timeouts
  def set_statement_timeout(_repo, _timeout_ms), do: :ok

  @impl true
  # No-op: SQLite does not support search_path
  def set_search_path(_repo, _search_path), do: :ok

  @impl true
  def format_error(%Exqlite.Error{} = e) do
    "SQLite Error: " <> (Map.get(e, :message) || Exception.message(e))
  end

  def format_error(other), do: Lotus.Adapter.Default.format_error(other)

  @impl true
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  def handled_errors, do: [Exqlite.Error]
end
