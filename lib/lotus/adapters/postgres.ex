defmodule Lotus.Adapter.Postgres do
  @moduledoc false

  @behaviour Lotus.Adapter

  @postgrex_error Module.concat([:Postgrex, :Error])

  @impl true
  def set_read_only(repo) do
    repo.query!("SET LOCAL transaction_read_only = on")
    :ok
  end

  @impl true
  def set_statement_timeout(repo, timeout_ms) do
    repo.query!("SET LOCAL statement_timeout = #{timeout_ms}")
    :ok
  end

  @impl true
  def set_search_path(repo, search_path) when is_binary(search_path) do
    repo.query!("SET LOCAL search_path = #{search_path}")
    :ok
  end

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @postgrex_error do
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
  end

  def format_error(other), do: Lotus.Adapter.Default.format_error(other)

  @impl true
  def param_placeholder(idx, _var, :date), do: "$#{idx}::date"
  def param_placeholder(idx, _var, :datetime), do: "$#{idx}::timestamp"
  def param_placeholder(idx, _var, :time), do: "$#{idx}::time"
  def param_placeholder(idx, _var, :number), do: "$#{idx}::numeric"
  def param_placeholder(idx, _var, :integer), do: "$#{idx}::integer"
  def param_placeholder(idx, _var, :boolean), do: "$#{idx}::boolean"
  def param_placeholder(idx, _var, :json), do: "$#{idx}::jsonb"
  def param_placeholder(idx, _var, _type), do: "$#{idx}"

  @impl true
  def handled_errors, do: [Postgrex.Error]

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"
    prefix = repo.config()[:migration_default_prefix] || "public"

    [
      {"pg_catalog", ~r/.*/},
      {"information_schema", ~r/.*/},
      {prefix, ms},
      {prefix, "lotus_queries"}
    ]
  end
end
