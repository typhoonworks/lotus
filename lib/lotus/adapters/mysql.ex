defmodule Lotus.Adapter.MySQL do
  @moduledoc false

  @behaviour Lotus.Adapter
  require Logger

  @myxql_error Module.concat([:MyXQL, :Error])

  @impl true
  def set_read_only(repo) do
    repo.query!("SET SESSION TRANSACTION READ ONLY")
    :ok
  end

  @impl true
  def set_statement_timeout(repo, timeout_ms) do
    repo.query!("SET SESSION max_execution_time = #{timeout_ms}")
    :ok
  end

  @impl true
  # No-op: MySQL does not have search_path concept
  def set_search_path(_repo, _search_path), do: :ok

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @myxql_error do
    case e do
      %{mysql: %{code: code, message: message}} when is_binary(message) ->
        "MySQL Error (#{code}): #{message}"

      %{message: message} when is_binary(message) ->
        "MySQL Error: #{message}"

      _ ->
        Exception.message(e)
    end
  end

  def format_error(other), do: Lotus.Adapter.Default.format_error(other)

  @impl true
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  def handled_errors, do: [MyXQL.Error]

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"

    [
      {"information_schema", ~r/.*/},
      {"mysql", ~r/.*/},
      {"performance_schema", ~r/.*/},
      {"sys", ~r/.*/},
      {nil, ms},
      {nil, "lotus_queries"}
    ]
  end
end
