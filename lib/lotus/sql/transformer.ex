defmodule Lotus.SQL.Transformer do
  @moduledoc """
  Transforms SQL queries for database-specific syntax compatibility.
  """

  @doc """
  Transforms SQL query for the target database type.
  """
  @spec transform(String.t(), atom()) :: String.t()
  def transform(sql, source_type) do
    sql
    |> transform_intervals(source_type)
    |> transform_quoted_wildcards(source_type)
    |> strip_quoted_variables()
  end

  # Convert quoted wildcard patterns around variable placeholders into
  # database-specific concatenation so parameters are not embedded inside
  # string literals (which breaks parameter binding and EXPLAIN).
  #
  # Examples:
  #   '%{{q}}%' -> '%' || {{q}} || '%'
  #   '{{q}}%'  -> {{q}} || '%'
  #   '%{{q}}'  -> '%' || {{q}}
  # For MySQL, we use CONCAT('%', {{q}}, '%') variants instead of ||.
  defp transform_quoted_wildcards(sql, source_type) do
    Regex.replace(~r/'([^']*)'/, sql, fn full ->
      content = String.slice(full, 1..-2//1)

      case wildcard_var(content) do
        {:both, var} -> build_concat(source_type, ["'%'", "{{#{var}}}", "'%'"])
        {:left, var} -> build_concat(source_type, ["'%'", "{{#{var}}}"])
        {:right, var} -> build_concat(source_type, ["{{#{var}}}", "'%'"])
        :no -> full
      end
    end)
  end

  defp wildcard_var(content) do
    cond do
      # %{{var}}%
      Regex.match?(~r/^%\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}%$/, content) ->
        [_, var] = Regex.run(~r/^%\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}%$/, content)
        {:both, var}

      # %{{var}}
      Regex.match?(~r/^%\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}$/, content) ->
        [_, var] = Regex.run(~r/^%\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}$/, content)
        {:left, var}

      # {{var}}%
      Regex.match?(~r/^\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}%$/, content) ->
        [_, var] = Regex.run(~r/^\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}%$/, content)
        {:right, var}

      true ->
        :no
    end
  end

  defp build_concat(:mysql, parts) do
    "CONCAT(" <> Enum.join(parts, ", ") <> ")"
  end

  defp build_concat(_other, parts) do
    Enum.join(parts, " || ")
  end

  defp transform_intervals(sql, source_type) do
    if contains_interval_pattern?(sql) do
      transform_interval_syntax(sql, source_type)
    else
      sql
    end
  end

  defp contains_interval_pattern?(sql) do
    String.contains?(sql, "INTERVAL") and String.contains?(sql, "{{")
  end

  defp transform_interval_syntax(sql, :postgres) do
    sql
    # INTERVAL {{interval}} -> ({{interval}})::interval
    # Must not match MySQL's INTERVAL {{n}} UNIT pattern
    |> then(fn s ->
      Regex.replace(
        ~r/INTERVAL\s+\{\{\s*(\w+)\s*\}\}(?!\s+(DAY|HOUR|MINUTE|SECOND|WEEK|MONTH|YEAR)\b)/i,
        s,
        fn _, var -> "({{#{var}}}::text)::interval" end
      )
    end)
    # INTERVAL '{{days}} {{unit}}' -> ((CAST({{days}} AS text) || ' ' || {{unit}})::interval)
    |> then(fn s ->
      Regex.replace(
        ~r/INTERVAL\s*'\s*\{\{\s*(\w+)\s*\}\}\s+\{\{\s*(\w+)\s*\}\}\s*'/i,
        s,
        fn _, num_var, unit_var ->
          "((CAST({{#{num_var}}} AS text) || ' ' || {{#{unit_var}}})::interval)"
        end
      )
    end)
    # INTERVAL '{{var}}' -> CAST({{var}} AS interval)
    |> then(fn s ->
      Regex.replace(
        ~r/INTERVAL\s*'\s*\{\{\s*(\w+)\s*\}\}\s*'/i,
        s,
        fn _, var -> "CAST({{#{var}}} AS interval)" end
      )
    end)
    # INTERVAL '7 {{unit}}' -> (('7 ' || {{unit}})::interval)
    |> then(fn s ->
      Regex.replace(
        ~r/INTERVAL\s*'\s*([0-9]+)\s+\{\{\s*(\w+)\s*\}\}\s*'/i,
        s,
        fn _, num, unit_var -> "(( '#{num} ' || {{#{unit_var}}} )::interval)" end
      )
    end)
    # '{{n}} unit' -> make_interval(units => {{n}}::integer)
    |> then(fn s ->
      Regex.replace(
        ~r/INTERVAL\s+'\{\{(\w+)\}\}\s+(day|hour|minute|second|week|month|year)s?'/i,
        s,
        fn _, var, unit ->
          plural_unit = ensure_plural(unit)
          "make_interval(#{plural_unit} => ({{#{var}}})::integer)"
        end
      )
    end)
  end

  # SQLite/MySQL don't support PostgreSQL-style INTERVAL syntax
  defp transform_interval_syntax(sql, _), do: sql

  defp ensure_plural("day"), do: "days"
  defp ensure_plural("hour"), do: "hours"
  defp ensure_plural("minute"), do: "minutes"
  defp ensure_plural("second"), do: "seconds"
  defp ensure_plural("week"), do: "weeks"
  defp ensure_plural("month"), do: "months"
  defp ensure_plural("year"), do: "years"

  defp ensure_plural(unit) when is_binary(unit) do
    unit = String.downcase(unit)
    if String.ends_with?(unit, "s"), do: unit, else: unit <> "s"
  end

  defp strip_quoted_variables(sql) do
    # Safe: '{{email}}' -> {{email}}, '{{id}}'::int -> {{id}}::int
    # Unsafe: '%{{q}}%' (leaves unchanged)
    String.replace(sql, ~r/'([^']*)'/, fn full_match ->
      content = String.slice(full_match, 1..-2//1)

      if Regex.match?(~r/^\{\{[A-Za-z_][A-Za-z0-9_]*\}\}$/, content) do
        content
      else
        full_match
      end
    end)
  end
end
