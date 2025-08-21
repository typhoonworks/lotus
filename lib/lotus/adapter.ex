defmodule Lotus.Adapter do
  @moduledoc """
  Database adapter-specific functionality for Lotus.

  Handles differences between database adapters like PostgreSQL, SQLite, etc.
  """

  @doc """
  Sets read-only mode for the given repository's adapter.
  """
  def set_read_only(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        repo.query!("SET LOCAL transaction_read_only = on")

      Ecto.Adapters.SQLite3 ->
        # SQLite doesn't support read-only transactions, but SELECT queries are inherently safe
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Sets statement timeout for the given repository's adapter.
  """
  def set_statement_timeout(repo, timeout_ms) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        repo.query!("SET LOCAL statement_timeout = #{timeout_ms}")

      Ecto.Adapters.SQLite3 ->
        # SQLite doesn't support statement_timeout
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Sets search_path for the given repository's adapter.

  Only affects PostgreSQL; other adapters ignore this setting.
  Uses SET LOCAL to scope the change to the current transaction.
  """
  def set_search_path(repo, search_path) when is_binary(search_path) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        repo.query!("SET LOCAL search_path = #{search_path}")

      _ ->
        :ok
    end
  end

  def set_search_path(_repo, _search_path), do: :ok

  @doc """
  Formats database errors into a consistent format.
  """
  def format_error(%Postgrex.Error{postgres: %{code: :syntax_error, message: msg}}) do
    "SQL syntax error: #{msg}"
  end

  def format_error(%Postgrex.Error{postgres: %{code: :undefined_table, message: msg}}) do
    "SQL error: #{msg}"
  end

  def format_error(%Postgrex.Error{postgres: %{code: :undefined_column, message: msg}}) do
    "SQL error: #{msg}"
  end

  def format_error(%Postgrex.Error{postgres: %{message: msg}}) when is_binary(msg) do
    "SQL error: #{msg}"
  end

  def format_error(%Postgrex.Error{message: msg}) when is_binary(msg) do
    "SQL error: #{msg}"
  end

  def format_error(%Exqlite.Error{} = err) do
    "SQLite Error: #{err.message}"
  end

  def format_error(%ArgumentError{message: msg}) do
    msg
  end

  def format_error(%DBConnection.EncodeError{message: msg}) do
    msg
  end

  def format_error(err) when is_binary(err) do
    err
  end

  def format_error(err) do
    "Database Error: #{inspect(err)}"
  end
end
