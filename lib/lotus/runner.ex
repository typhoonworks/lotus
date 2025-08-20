defmodule Lotus.Runner do
  @moduledoc """
  Read-only SQL execution with safety checks, param binding, and result shaping.
  """

  alias Lotus.{Adapter, QueryResult}

  @type repo :: module()
  @type sql :: String.t()
  @type params :: list()
  @type query_result :: QueryResult.t()
  @type opts :: [
          timeout: non_neg_integer(),
          statement_timeout_ms: non_neg_integer(),
          read_only: boolean()
        ]

  # Deny list for dangerous operations (defense-in-depth)
  # The real safety is the DB-level read-only transaction guard
  @deny ~r/\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|VACUUM|ANALYZE|CALL|LOCK)\b/i

  @spec run_sql(repo(), sql(), params(), opts()) ::
          {:ok, query_result()} | {:error, term()}
  def run_sql(repo, sql, params \\ [], opts \\ []) when is_binary(sql) and is_list(params) do
    with :ok <- assert_single_statement(sql),
         :ok <- assert_not_denied(sql) do
      exec_read_only(repo, sql, params, opts)
    end
  end

  defp exec_read_only(repo, sql, params, opts) do
    read_only? = Keyword.get(opts, :read_only, true)
    stmt_ms = Keyword.get(opts, :statement_timeout_ms, 5_000)
    db_timeout = Keyword.get(opts, :timeout, 15_000)

    repo.transaction(
      fn ->
        if read_only?, do: Adapter.set_read_only(repo)
        Adapter.set_statement_timeout(repo, stmt_ms)

        case repo.query(sql, params, timeout: db_timeout) do
          {:ok, %{columns: cols, rows: rows}} ->
            {:ok, QueryResult.new(cols, rows)}

          {:error, err} ->
            repo.rollback(Adapter.format_error(err))

          other ->
            other
        end
      end,
      timeout: db_timeout
    )
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Adapter.format_error(e)}
  end

  defp assert_single_statement(sql) do
    # Disallow semicolons to avoid accidental multi-statements (defensive)
    if String.contains?(sql, ";"), do: {:error, "Only a single statement is allowed"}, else: :ok
  end

  defp assert_not_denied(sql) do
    if Regex.match?(@deny, sql), do: {:error, "Only read-only queries are allowed"}, else: :ok
  end
end
