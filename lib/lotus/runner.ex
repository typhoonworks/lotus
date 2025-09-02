defmodule Lotus.Runner do
  @moduledoc """
  Read-only SQL execution with safety checks, param binding, and result shaping.
  """

  alias Lotus.{Source, Result, Preflight}

  @type repo :: module()
  @type sql :: String.t()
  @type params :: list()
  @type query_result :: Result.t()
  @type opts :: [
          timeout: non_neg_integer(),
          statement_timeout_ms: non_neg_integer(),
          read_only: boolean(),
          search_path: String.t() | nil
        ]

  # Deny list for dangerous operations (defense-in-depth)
  # The real safety is the DB-level read-only transaction guard
  @deny ~r/\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|VACUUM|ANALYZE|CALL|LOCK)\b/i

  @spec run_sql(repo(), sql(), params(), opts()) ::
          {:ok, query_result()} | {:error, term()}
  def run_sql(repo, sql, params \\ [], opts \\ []) when is_binary(sql) and is_list(params) do
    with :ok <- assert_single_statement(sql),
         :ok <- assert_not_denied(sql),
         :ok <- preflight_visibility(repo, sql, params, opts) do
      exec_read_only(repo, sql, params, opts)
    end
  end

  defp exec_read_only(repo, sql, params, opts) do
    Source.execute_in_transaction(
      repo,
      fn ->
        case repo.query(sql, params, timeout: Keyword.get(opts, :timeout, 15_000)) do
          {:ok, %{columns: cols, rows: rows}} ->
            {:ok, Result.new(cols, rows)}

          {:error, err} ->
            repo.rollback(Source.format_error(err))

          other ->
            other
        end
      end,
      opts
    )
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Source.format_error(e)}
  end

  # Allow a single statement with an optional trailing semicolon.
  # Reject any additional top-level semicolons (outside strings/comments).
  defp assert_single_statement(sql) do
    s = String.trim(sql)

    s =
      if String.ends_with?(s, ";") do
        s
        |> String.trim_trailing()
        |> String.trim_trailing(";")
        |> String.trim_trailing()
      else
        s
      end

    if has_top_level_semicolon?(s) do
      {:error, "Only a single statement is allowed"}
    else
      :ok
    end
  end

  defp has_top_level_semicolon?(bin), do: scan_semicolons(bin, :code)

  # State machine that skips semicolons inside:
  # - single-quoted strings
  # - double-quoted identifiers
  # - PostgreSQL dollar-quoted strings ($tag$ ... $tag$ or $ ... $)
  # - line comments (-- ...\n)
  # - block comments (/* ... */)
  defp scan_semicolons(<<>>, _state), do: false

  defp scan_semicolons(<<?;, _::binary>>, :code), do: true

  defp scan_semicolons(<<"--", rest::binary>>, :code),
    do: scan_semicolons(skip_to_eol(rest), :code)

  defp scan_semicolons(<<"/*", rest::binary>>, :code),
    do: scan_semicolons(skip_block_comment(rest), :code)

  defp scan_semicolons(<<"'", rest::binary>>, :code),
    do: scan_semicolons(skip_single_quoted(rest), :code)

  defp scan_semicolons(<<"\"", rest::binary>>, :code),
    do: scan_semicolons(skip_double_quoted(rest), :code)

  defp scan_semicolons(<<"$", rest::binary>>, :code) do
    case take_dollar_tag(rest, "") do
      {:tag, tag, after_tag} -> scan_semicolons(skip_dollar_quoted(after_tag, tag), :code)
      :no_tag -> scan_semicolons(rest, :code)
    end
  end

  defp scan_semicolons(<<_::utf8, rest::binary>>, :code),
    do: scan_semicolons(rest, :code)

  defp skip_to_eol(<<>>), do: <<>>
  defp skip_to_eol(<<"\n", rest::binary>>), do: rest
  defp skip_to_eol(<<_::utf8, rest::binary>>), do: skip_to_eol(rest)

  defp skip_block_comment(<<>>), do: <<>>
  defp skip_block_comment(<<"*/", rest::binary>>), do: rest
  defp skip_block_comment(<<_::utf8, rest::binary>>), do: skip_block_comment(rest)

  defp skip_single_quoted(<<>>), do: <<>>
  defp skip_single_quoted(<<"''", rest::binary>>), do: skip_single_quoted(rest)
  defp skip_single_quoted(<<"'", rest::binary>>), do: rest
  defp skip_single_quoted(<<_::utf8, rest::binary>>), do: skip_single_quoted(rest)

  defp skip_double_quoted(<<>>), do: <<>>
  defp skip_double_quoted(<<"\"\"", rest::binary>>), do: skip_double_quoted(rest)
  defp skip_double_quoted(<<"\"", rest::binary>>), do: rest
  defp skip_double_quoted(<<_::utf8, rest::binary>>), do: skip_double_quoted(rest)

  defp take_dollar_tag(<<"$", rest::binary>>, acc), do: {:tag, acc, rest}

  defp take_dollar_tag(<<c, rest::binary>>, acc)
       when c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?_,
       do: take_dollar_tag(rest, <<acc::binary, c>>)

  defp take_dollar_tag(_, _), do: :no_tag

  defp skip_dollar_quoted(bin, tag) do
    closer = "$" <> tag <> "$"

    case :binary.match(bin, closer) do
      :nomatch -> <<>>
      {pos, len} -> :binary.part(bin, pos + len, byte_size(bin) - pos - len)
    end
  end

  defp assert_not_denied(sql) do
    if Regex.match?(@deny, sql), do: {:error, "Only read-only queries are allowed"}, else: :ok
  end

  defp preflight_visibility(repo, sql, params, opts) do
    if needs_preflight?(sql) do
      repo_name =
        Lotus.Config.data_repos()
        |> Enum.find_value(fn {name, mod} -> if mod == repo, do: name end) || "default"

      search_path = Keyword.get(opts, :search_path)

      case Preflight.authorize(repo, repo_name, sql, params, search_path) do
        :ok -> :ok
        {:error, msg} -> {:error, msg}
      end
    else
      :ok
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp needs_preflight?(sql) do
    s = scrub(sql)

    cond do
      starts_with?(s, "EXPLAIN") -> false
      starts_with?(s, "PRAGMA") -> false
      starts_with?(s, "SHOW") -> false
      true -> true
    end
  end

  defp scrub(sql) do
    sql
    |> String.replace(~r/--.*$/m, "")
    |> String.replace(~r/\/\*[\s\S]*?\*\//, "")
    |> String.trim_leading()
    |> upcase_head(12)
  end

  defp upcase_head(s, n) do
    {head, tail} = String.split_at(s, n)
    String.upcase(head) <> tail
  end

  defp starts_with?(s, prefix), do: String.starts_with?(s, prefix)
end
