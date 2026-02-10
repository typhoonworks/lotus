defmodule Lotus.Sources.SQLServer do
  @moduledoc false

  @behaviour Lotus.Source

  alias Lotus.Sources.Default

  @mssql_error Module.concat([:Tds, :Error])

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    read_only? = Keyword.get(opts, :read_only, true)
    timeout = Keyword.get(opts, :timeout, 15_000)

    repo.transaction(
      fn ->
        if read_only?, do: repo.query!("SET TRANSACTION ISOLATION LEVEL SNAPSHOT;")

        fun.()
      end,
      timeout: timeout
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def set_statement_timeout(_repo, _timeout_ms), do: :ok

  @impl true
  # No-op: SQL does not have search_path concept. 
  # Would need to pass `prefix: ` down to each query instead.
  def set_search_path(_repo, _search_path), do: :ok

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @mssql_error do
    case e do
      %{mssql: [msg_text: message, number: code]} when is_binary(message) ->
        "SQL Server Error (#{code}): #{message}"

      %{message: message} when is_binary(message) ->
        "SQL Server Error: #{message}"

      _ ->
        Exception.message(e)
    end
  end

  @impl true
  def handled_errors, do: [TDS.Error]
end
