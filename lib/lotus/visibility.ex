defmodule Lotus.Visibility do
  @moduledoc """
  Table visibility filtering for Lotus.

  Built-ins deny common metadata/system relations; user config can add allow/deny.
  """

  alias Lotus.Config

  @doc """
  Checks if a relation (schema, table) is allowed for the given data repo name.
  """
  @spec allowed_relation?(String.t(), {String.t() | nil, String.t()}) :: boolean()
  def allowed_relation?(repo_name, {schema, table}) do
    rules = Config.rules_for_repo_name(repo_name)

    builtin = builtin_denies(repo_name)

    builtin_denied = deny_hit?(builtin, schema, table)
    allowed = allow_pass?(rules[:allow], schema, table)
    user_denied = deny_hit?(rules[:deny], schema, table)

    (allowed || rules[:allow] in [nil, []]) and not (builtin_denied or user_denied)
  end

  defp builtin_denies(repo_name) do
    repo = Config.data_repos() |> Map.get(repo_name)

    if is_nil(repo) do
      [
        {"pg_catalog", ~r/.*/},
        {"information_schema", ~r/.*/},
        {"public", "schema_migrations"},
        {nil, "schema_migrations"},
        {nil, ~r/^sqlite_/},
        {"public", "lotus_queries"},
        {nil, "lotus_queries"}
      ]
    else
      adapter = repo.__adapter__()
      ms = repo.config()[:migration_source] || "schema_migrations"

      case adapter do
        Ecto.Adapters.Postgres ->
          prefix = repo.config()[:migration_default_prefix] || "public"

          [
            {"pg_catalog", ~r/.*/},
            {"information_schema", ~r/.*/},
            {prefix, ms},
            {prefix, "lotus_queries"}
          ]

        Ecto.Adapters.SQLite3 ->
          [
            {nil, ~r/^sqlite_/},
            {nil, ms},
            {nil, "lotus_queries"}
          ]

        _ ->
          # Conservative default for unknown adapters
          [
            {"pg_catalog", ~r/.*/},
            {"information_schema", ~r/.*/},
            {nil, ~r/^sqlite_/},
            {nil, "schema_migrations"},
            {"public", "schema_migrations"},
            {"public", "lotus_queries"},
            {nil, "lotus_queries"}
          ]
      end
    end
  end

  defp allow_pass?(nil, _s, _t), do: true
  defp allow_pass?([], _s, _t), do: true
  defp allow_pass?(rules, s, t), do: any_match?(rules, s, t)

  defp deny_hit?(nil, _s, _t), do: false
  defp deny_hit?([], _s, _t), do: false
  defp deny_hit?(rules, s, t), do: any_match?(rules, s, t)

  defp any_match?(rules, s, t) do
    Enum.any?(rules, fn
      {schema_pat, table_pat} ->
        pattern_match?(schema_pat, s) and pattern_match?(table_pat, t)

      tbl when is_binary(tbl) ->
        s in [nil, ""] and pattern_match?(tbl, t)

      other ->
        other == {s, t}
    end)
  end

  # IMPORTANT: only treat `nil` schema pattern as a match when the relation's schema is nil/""
  # (prevents SQLite-intended rules from matching Postgres relations)
  defp pattern_match?(%Regex{} = rx, val) when is_binary(val), do: Regex.match?(rx, val)
  defp pattern_match?(%Regex{}, nil), do: false
  defp pattern_match?(str, val) when is_binary(str) and is_binary(val), do: str == val
  defp pattern_match?(nil, s) when s in [nil, ""], do: true
  defp pattern_match?(nil, _), do: false
  defp pattern_match?(_, _), do: false
end
