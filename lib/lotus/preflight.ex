defmodule Lotus.Preflight do
  @moduledoc """
  SQL preflight authorization for Lotus.

  Delegates to the adapter's `extract_accessed_resources/4` callback to
  discover which tables/relations a query will access, then checks those
  relations against visibility rules before execution.

  This provides defense-in-depth by blocking queries that would access
  denied tables, even if they're accessed through views or complex subqueries.
  """

  alias Lotus.Preflight.Relations
  alias Lotus.Source.Adapter
  alias Lotus.Visibility

  @doc """
  Authorizes a SQL query by checking all relations it would access.

  Delegates resource extraction to the adapter, then validates each
  relation against the visibility rules.

  ## Examples

      authorize(adapter, "SELECT * FROM users", [], nil)
      #=> :ok

      authorize(adapter, "SELECT * FROM schema_migrations", [], "reporting, public")
      #=> {:error, "Query touches a blocked table"}
  """
  @spec authorize(Adapter.t(), String.t(), list(), String.t() | nil) ::
          :ok | {:error, String.t()}
  def authorize(%Adapter{} = adapter, sql, params, search_path \\ nil) do
    opts = if search_path, do: [search_path: search_path], else: []

    case Adapter.extract_accessed_resources(adapter, sql, params, opts) do
      {:ok, relations} ->
        rels = MapSet.to_list(relations)
        check_relations_visibility(rels, adapter.name)

      {:error, e} ->
        {:error, normalize_preflight_error(e, adapter)}

      :skip ->
        :ok
    end
  end

  defp check_relations_visibility(rels, source_name) do
    {allowed, blocked} = Enum.split_with(rels, &Visibility.allowed_relation?(source_name, &1))

    if blocked == [] do
      Relations.put(allowed)
      :ok
    else
      {:error, "Query touches blocked table(s): #{format_relations(blocked)}"}
    end
  end

  defp format_relations(relations) do
    relations
    |> Enum.map(fn
      {nil, table} -> table
      {schema, table} -> "#{schema}.#{table}"
    end)
  end

  defp normalize_preflight_error(e, _adapter) when is_binary(e) do
    strip_explain_query_tail(e)
  end

  defp normalize_preflight_error(e, adapter) do
    e
    |> then(&Adapter.format_error(adapter, &1))
    |> strip_explain_query_tail()
  end

  defp strip_explain_query_tail(msg) do
    Regex.replace(~r/\n?query:\s*EXPLAIN[\s\S]*\z/i, msg, "")
    |> String.trim_trailing()
  end
end
