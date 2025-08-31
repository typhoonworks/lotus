defmodule Lotus.Sources.MySQL do
  @moduledoc false

  @behaviour Lotus.Source
  require Logger

  @myxql_error Module.concat([:MyXQL, :Error])

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    read_only? = Keyword.get(opts, :read_only, true)

    stmt_ms =
      case Keyword.get(opts, :statement_timeout_ms, 5_000) do
        v when is_integer(v) and v >= 0 -> v
        _ -> 5_000
      end

    timeout = Keyword.get(opts, :timeout, 15_000)

    # Snapshot current session state
    prev_iso =
      case read_iso_var(repo) do
        {:ok, iso} -> iso
        _ -> nil
      end

    prev_ro =
      case repo.query("SELECT @@session.transaction_read_only") do
        {:ok, %{rows: [[ro]]}} -> ro
        _ -> nil
      end

    prev_met =
      case repo.query("SELECT @@session.max_execution_time") do
        {:ok, %{rows: [[met]]}} -> met || 0
        _ -> 0
      end

    try do
      if read_only?, do: repo.query!("SET SESSION TRANSACTION READ ONLY")
      repo.query!("SET SESSION max_execution_time = #{stmt_ms}")
      repo.transaction(fun, timeout: timeout)
    after
      # Restore read-only state
      cond do
        prev_ro in [1, "1", true] -> repo.query!("SET SESSION TRANSACTION READ ONLY")
        prev_ro in [0, "0", false] -> repo.query!("SET SESSION TRANSACTION READ WRITE")
        true -> repo.query!("SET SESSION TRANSACTION READ WRITE")
      end

      # Restore isolation
      if prev_iso, do: restore_iso(repo, prev_iso)

      # Restore timeout
      timeout_val = if is_integer(prev_met) and prev_met >= 0, do: prev_met, else: 0
      repo.query!("SET SESSION max_execution_time = #{timeout_val}")
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp read_iso_var(repo) do
    # Try 8.0+ name first
    case repo.query("SELECT @@session.transaction_isolation") do
      {:ok, %{rows: [[iso]]}} ->
        {:ok, iso}

      {:error, _} ->
        # Fallback for older versions
        case repo.query("SELECT @@session.tx_isolation") do
          {:ok, %{rows: [[iso]]}} -> {:ok, iso}
          {:error, err} -> {:error, err}
        end
    end
  end

  defp restore_iso(repo, iso) do
    case iso do
      "READ-COMMITTED" ->
        repo.query!("SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED")

      "REPEATABLE-READ" ->
        repo.query!("SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ")

      "READ-UNCOMMITTED" ->
        repo.query!("SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")

      "SERIALIZABLE" ->
        repo.query!("SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE")

      _ ->
        :ok
    end
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

  def format_error(other), do: Lotus.Sources.Default.format_error(other)

  @impl true
  def param_placeholder(_idx, _var, :date), do: "CAST(? AS DATE)"
  def param_placeholder(_idx, _var, :datetime), do: "CAST(? AS DATETIME)"
  def param_placeholder(_idx, _var, :time), do: "CAST(? AS TIME)"
  def param_placeholder(_idx, _var, :number), do: "CAST(? AS DECIMAL)"
  def param_placeholder(_idx, _var, :integer), do: "CAST(? AS SIGNED)"
  def param_placeholder(_idx, _var, :boolean), do: "CAST(? AS UNSIGNED)"
  def param_placeholder(_idx, _var, :json), do: "CAST(? AS JSON)"
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
