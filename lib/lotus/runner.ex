defmodule Lotus.Runner do
  @moduledoc """
  SQL execution with safety checks, param binding, and result shaping.

  By default, all queries are read-only. Destructive operations (INSERT, UPDATE,
  DELETE, DDL) are blocked at both the application and database level. Pass
  `read_only: false` to allow write operations.
  """

  alias Lotus.{Middleware, Preflight, Result, Source, Telemetry, Visibility}
  alias Lotus.Preflight.Relations
  alias Lotus.Source.Adapter
  alias Lotus.Visibility.Policy

  @type sql :: String.t()
  @type params :: list()
  @type query_result :: Result.t()
  @type opts :: [
          timeout: non_neg_integer(),
          statement_timeout_ms: non_neg_integer(),
          read_only: boolean(),
          search_path: String.t() | nil
        ]

  # Deny list for dangerous operations (defense-in-depth).
  # Skipped when `read_only: false` is passed in opts.
  # The DB-level read-only transaction guard provides an additional safety layer.
  @deny ~r/\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|VACUUM|ANALYZE|CALL|LOCK)\b/i

  @spec run_sql(Adapter.t(), sql(), params(), opts()) ::
          {:ok, query_result()} | {:error, term()}
  def run_sql(%Adapter{} = adapter, sql, params \\ [], opts \\ [])
      when is_binary(sql) and is_list(params) do
    telemetry_meta = %{repo: adapter.name, sql: sql, params: params}
    start_time = Telemetry.query_start(telemetry_meta)
    read_only = Keyword.get(opts, :read_only, true)

    context = Keyword.get(opts, :context)

    result =
      with :ok <- assert_single_statement(sql),
           :ok <- assert_not_denied(sql, read_only),
           :ok <- preflight_visibility(adapter, sql, params, opts),
           :ok <- run_before_query(adapter, sql, params, context),
           {:ok, %Result{} = res} <- exec_read_only(adapter, sql, params, opts),
           {:ok, %Result{} = res} <- run_after_query(adapter, sql, params, res, context) do
        {:ok, res}
      end

    case result do
      {:ok, %Result{} = res} ->
        Telemetry.query_stop(
          start_time,
          Map.merge(telemetry_meta, %{row_count: res.num_rows, result: res})
        )

        {:ok, res}

      {:error, _} = error ->
        Telemetry.query_exception(start_time, :error, error, [], telemetry_meta)
        error
    end
  end

  defp exec_read_only(%Adapter{} = adapter, sql, params, opts) do
    Adapter.transaction(
      adapter,
      fn _state ->
        timeout = Keyword.get(opts, :timeout, 15_000)

        {elapsed_us, res} =
          :timer.tc(fn ->
            Adapter.execute_query(adapter, sql, params, opts ++ [timeout: timeout])
          end)

        handle_query_result(res, elapsed_us, adapter)
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

  defp handle_query_result(
         {:ok, %{columns: cols, rows: rows} = raw},
         elapsed_us,
         %Adapter{} = adapter
       ) do
    num_rows = Map.get(raw, :num_rows, length(rows || []))
    command = normalize_command(Map.get(raw, :command))
    duration_ms = System.convert_time_unit(elapsed_us, :microsecond, :millisecond)

    rels = Relations.take()

    policies =
      Enum.map(cols || [], fn c -> Visibility.column_policy_for(adapter.name, rels, c) end)

    case enforce_column_policies(cols || [], rows || [], policies) do
      {:error, msg} ->
        {:error, msg}

      {final_cols, final_rows} ->
        {:ok,
         Result.new(final_cols, final_rows,
           num_rows: num_rows,
           duration_ms: duration_ms,
           command: command,
           meta: Map.take(raw, [:connection_id, :messages])
         )}
    end
  end

  defp handle_query_result({:error, err}, _elapsed_us, _adapter) do
    {:error, err}
  end

  defp handle_query_result(other, _elapsed_us, _adapter) do
    other
  end

  defp normalize_command(nil), do: nil
  defp normalize_command(cmd) when is_atom(cmd), do: Atom.to_string(cmd)
  defp normalize_command(cmd) when is_binary(cmd), do: cmd
  defp normalize_command(cmd), do: inspect(cmd)

  defp enforce_column_policies(cols, rows, policies) do
    error_cols =
      cols
      |> Enum.zip(policies)
      |> Enum.filter(fn {_c, pol} -> Policy.causes_error?(pol) end)
      |> Enum.map(fn {c, _} -> c end)

    if error_cols != [] do
      {:error, "Query selects hidden column(s): #{Enum.join(error_cols, ", ")}"}
    else
      omit_idx =
        policies
        |> Enum.with_index()
        |> Enum.filter(fn {pol, _i} -> Policy.omits_column?(pol) end)
        |> Enum.map(fn {_pol, i} -> i end)
        |> MapSet.new()

      mask_map = build_mask_map(policies)

      new_cols =
        cols
        |> Enum.with_index()
        |> Enum.reject(fn {_c, i} -> MapSet.member?(omit_idx, i) end)
        |> Enum.map(&elem(&1, 0))

      new_rows = Enum.map(rows, fn row -> process_row(row, omit_idx, mask_map) end)

      {new_cols, new_rows}
    end
  end

  defp build_mask_map(policies) do
    policies
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {pol, i}, acc ->
      if Policy.requires_mask?(pol), do: Map.put(acc, i, pol), else: acc
    end)
  end

  defp process_row(row, omit_idx, mask_map) do
    row
    |> Enum.with_index()
    |> Enum.reject(fn {_v, i} -> MapSet.member?(omit_idx, i) end)
    |> Enum.map(fn {v, i} -> apply_mask_policy(v, Map.get(mask_map, i)) end)
  end

  defp apply_mask_policy(value, nil), do: value
  defp apply_mask_policy(_value, %{mask: :null}), do: nil
  defp apply_mask_policy(_value, %{mask: {:fixed, fixed_value}}), do: fixed_value
  defp apply_mask_policy(value, %{mask: :sha256}), do: sha256_hex(to_string_safe(value))

  defp apply_mask_policy(value, %{mask: {:partial, opts}}),
    do: partial_mask(to_string_safe(value), opts)

  defp apply_mask_policy(_value, _), do: nil

  defp to_string_safe(nil), do: ""
  defp to_string_safe(v) when is_binary(v), do: v
  defp to_string_safe(v), do: to_string(v)

  defp sha256_hex(s) do
    :crypto.hash(:sha256, s) |> Base.encode16(case: :lower)
  end

  defp partial_mask(s, opts) when is_binary(s) do
    keep_last = Keyword.get(opts, :keep_last, 4)
    keep_first = Keyword.get(opts, :keep_first, 0)
    repl = Keyword.get(opts, :replacement, "*")

    len = String.length(s)
    left = min(keep_first, len)
    right = min(keep_last, max(len - left, 0))
    mid = max(len - left - right, 0)

    left_part = String.slice(s, 0, left)
    right_part = if right > 0, do: String.slice(s, len - right, right), else: ""
    masked = String.duplicate(repl, mid)
    left_part <> masked <> right_part
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

  # PostgreSQL supports nested block comments. Track depth so a nested `/*`
  # does not let the parser exit early on the first `*/`, which would let a
  # subsequent statement slip past `assert_single_statement/1`.
  defp skip_block_comment(rest), do: skip_block_comment(rest, 1)

  defp skip_block_comment(<<>>, _depth), do: <<>>
  defp skip_block_comment(<<"*/", rest::binary>>, 1), do: rest
  defp skip_block_comment(<<"*/", rest::binary>>, depth), do: skip_block_comment(rest, depth - 1)
  defp skip_block_comment(<<"/*", rest::binary>>, depth), do: skip_block_comment(rest, depth + 1)
  defp skip_block_comment(<<_::utf8, rest::binary>>, depth), do: skip_block_comment(rest, depth)

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

  defp run_before_query(%Adapter{} = adapter, sql, params, context) do
    payload = %{repo: adapter.name, sql: sql, params: params, context: context}

    case Middleware.run(:before_query, payload) do
      {:cont, _} -> :ok
      {:halt, reason} -> {:error, reason}
    end
  end

  defp run_after_query(%Adapter{} = adapter, sql, params, %Result{} = result, context) do
    payload = %{repo: adapter.name, sql: sql, params: params, result: result, context: context}

    case Middleware.run(:after_query, payload) do
      {:cont, %{result: res}} -> {:ok, res}
      {:halt, reason} -> {:error, reason}
    end
  end

  defp assert_not_denied(_sql, false = _read_only), do: :ok

  defp assert_not_denied(sql, _read_only) do
    if Regex.match?(@deny, sql), do: {:error, "Only read-only queries are allowed"}, else: :ok
  end

  defp preflight_visibility(%Adapter{} = adapter, sql, params, opts) do
    if needs_preflight?(sql) do
      search_path = Keyword.get(opts, :search_path)

      case Preflight.authorize(adapter, sql, params, search_path) do
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
