defmodule Lotus.Adapter do
  @moduledoc """
  Database adapter-specific functionality for Lotus.

  Handles differences between database adapters like PostgreSQL, SQLite, etc.
  """

  require Logger

  @doc "Sets read-only mode for the given repository's adapter."
  @spec set_read_only(Ecto.Repo.t()) :: :ok | no_return()
  def set_read_only(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        repo.query!("SET LOCAL transaction_read_only = on")
        :ok

      Ecto.Adapters.SQLite3 ->
        try do
          repo.query!("PRAGMA query_only = ON")
          :ok
        rescue
          error in [Exqlite.Error] ->
            if error.message =~ "no such pragma" or error.message =~ "unknown pragma" do
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

      _ ->
        :ok
    end
  end

  @doc "Sets statement timeout (ms) for the given repository's adapter."
  @spec set_statement_timeout(Ecto.Repo.t(), non_neg_integer()) :: :ok | no_return()
  def set_statement_timeout(repo, timeout_ms) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        repo.query!("SET LOCAL statement_timeout = #{timeout_ms}")
        :ok

      Ecto.Adapters.SQLite3 ->
        :ok

      _ ->
        :ok
    end
  end

  @doc "Sets search_path for the given repository's adapter."
  @spec set_search_path(Ecto.Repo.t(), String.t()) :: :ok | no_return()
  def set_search_path(repo, search_path) when is_binary(search_path) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        repo.query!("SET LOCAL search_path = #{search_path}")
        :ok

      _ ->
        :ok
    end
  end

  def set_search_path(_repo, _search_path), do: :ok

  @doc "Formats database errors into a consistent string."
  @spec format_error(any()) :: String.t()
  def format_error(%{__exception__: true, __struct__: mod} = e) do
    cond do
      mod == Postgrex.Error ->
        pg = Map.get(e, :postgres)

        cond do
          is_map(pg) and pg[:code] == :syntax_error and is_binary(pg[:message]) ->
            "SQL syntax error: #{pg[:message]}"

          is_map(pg) and is_binary(pg[:message]) ->
            "SQL error: #{pg[:message]}"

          is_binary(Map.get(e, :message)) ->
            "SQL error: #{Map.get(e, :message)}"

          true ->
            Exception.message(e)
        end

      mod == Exqlite.Error ->
        "SQLite Error: " <> (Map.get(e, :message) || Exception.message(e))

      true ->
        Exception.message(e)
    end
  end

  def format_error(%DBConnection.EncodeError{message: msg}), do: msg
  def format_error(%ArgumentError{message: msg}), do: msg
  def format_error(msg) when is_binary(msg), do: msg
  def format_error(other), do: "Database Error: #{inspect(other)}"

  @doc "Returns parameter style for the given repo or repo name."
  @spec param_style(nil | String.t() | module()) ::
          :postgres | :sqlite | :unknown
  def param_style(nil), do: :postgres

  def param_style(repo_name) when is_binary(repo_name) do
    repo = Lotus.Config.get_data_repo!(repo_name)
    param_style(repo)
  end

  def param_style(repo) when is_atom(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      _ -> :unknown
    end
  end
end
