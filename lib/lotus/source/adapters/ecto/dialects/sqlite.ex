defmodule Lotus.Source.Adapters.Ecto.Dialects.SQLite3 do
  @moduledoc false

  @behaviour Lotus.Source.Adapters.Ecto.Dialect

  require Logger

  alias Lotus.Source.Adapters.Ecto.Dialects.Default
  alias Lotus.SQL.FilterInjector
  alias Lotus.SQL.Identifier
  alias Lotus.SQL.SortInjector

  @exlite_error Module.concat([:Exqlite, :Error])

  @impl true
  def source_type, do: :sqlite

  @impl true
  def ecto_adapter, do: Ecto.Adapters.SQLite3

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    read_only? = Keyword.get(opts, :read_only, true)
    timeout = Keyword.get(opts, :timeout, 15_000)

    {pragma_supported?, prev_state} = setup_read_only_pragma(repo, read_only?)

    try do
      repo.transaction(fun, timeout: timeout)
    after
      restore_pragma_state(repo, pragma_supported?, prev_state)
    end
  end

  defp setup_read_only_pragma(_repo, false), do: {false, nil}

  defp setup_read_only_pragma(repo, true) do
    check_and_set_pragma(repo)
  rescue
    error in [Exqlite.Error] ->
      msg = error.message || Exception.message(error)

      if msg =~ "no such pragma" or msg =~ "unknown pragma" do
        log_pragma_warning()
        {false, nil}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp check_and_set_pragma(repo) do
    case repo.query("PRAGMA query_only") do
      {:ok, %{rows: [[prev]]}} ->
        repo.query!("PRAGMA query_only = ON")
        {true, prev}

      _ ->
        {false, nil}
    end
  end

  defp log_pragma_warning do
    Logger.warning("""
    SQLite version does not support PRAGMA query_only.
    Consider opening the DB in read-only mode
    (e.g., database=...&mode=ro or database=...&immutable=1).
    """)
  end

  defp restore_pragma_state(_repo, false, _prev_state), do: :ok

  defp restore_pragma_state(repo, true, prev_state) do
    restore = if prev_state in [0, 1], do: prev_state, else: 0
    repo.query!("PRAGMA query_only = #{restore}")
  rescue
    _ -> :ok
  end

  @impl true
  def set_statement_timeout(_repo, _timeout_ms), do: :ok

  @impl true
  def set_search_path(_repo, _search_path), do: :ok

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @exlite_error do
    "SQLite Error: " <> (Map.get(e, :message) || Exception.message(e))
  end

  def format_error(other), do: Default.format_error(other)

  @impl true
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  def limit_offset_placeholders(_limit_idx, _offset_idx) do
    {"?", "?"}
  end

  @impl true
  def handled_errors, do: [Exqlite.Error]

  @impl true
  def query_language, do: "sql:sqlite"

  @impl true
  def limit_query(statement, limit) do
    "SELECT * FROM (#{statement}) AS limited_query LIMIT #{limit}"
  end

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"

    [
      {nil, ~r/^sqlite_/},
      {nil, ms},
      {nil, "lotus_queries"},
      {nil, "lotus_query_visualizations"},
      {nil, "lotus_dashboards"},
      {nil, "lotus_dashboard_cards"},
      {nil, "lotus_dashboard_filters"},
      {nil, "lotus_dashboard_card_filter_mappings"}
    ]
  end

  @impl true
  def default_schemas(_repo) do
    []
  end

  @impl true
  def supports_feature?(:schema_hierarchy), do: false
  def supports_feature?(:search_path), do: false
  def supports_feature?(:make_interval), do: false
  def supports_feature?(:arrays), do: false
  def supports_feature?(:json), do: true
  def supports_feature?(_), do: false

  @impl true
  def hierarchy_label, do: "Tables"

  @impl true
  def example_query(table, _schema) do
    "SELECT value_column FROM #{table}"
  end

  @impl true
  def builtin_schema_denies(_repo) do
    []
  end

  @impl true
  def list_schemas(_repo) do
    []
  end

  @impl true
  def list_tables(repo, _schemas, _include_views?) do
    query = """
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name NOT LIKE 'sqlite_%'
    ORDER BY name
    """

    result = repo.query!(query)
    Enum.map(result.rows, fn [table_name] -> {nil, table_name} end)
  end

  @impl true
  def get_table_schema(repo, _schema, table_name) do
    Identifier.validate_identifier!(table_name, "table name")
    query = "PRAGMA table_info(#{table_name})"

    result = repo.query!(query)

    Enum.map(result.rows, fn row ->
      [_cid, name, type, notnull, default, pk] = row

      %{
        name: name,
        type: type,
        nullable: notnull == 0,
        default: default,
        primary_key: pk == 1
      }
    end)
  end

  @impl true
  def explain_plan(repo, sql, params, _opts) do
    explain_sql = "EXPLAIN QUERY PLAN " <> sql

    case repo.query(explain_sql, params) do
      {:ok, %{rows: rows}} ->
        plan_text =
          Enum.map_join(rows, "\n", fn row -> Enum.join(row, " | ") end)

        {:ok, plan_text}

      {:error, err} ->
        {:error, format_error(err)}
    end
  end

  @impl true
  def resolve_table_schema(_repo, _table, _schemas) do
    nil
  end

  @impl true
  def quote_identifier(identifier) do
    escaped = String.replace(identifier, "\"", "\"\"")
    ~s("#{escaped}")
  end

  @impl true
  def apply_filters(sql, params, filters) do
    FilterInjector.apply(sql, params, filters, &quote_identifier/1, fn _idx -> "?" end)
  end

  @impl true
  def apply_sorts(sql, sorts) do
    SortInjector.apply(sql, sorts, &quote_identifier/1)
  end

  alias Lotus.Source.Adapters.Ecto, as: EctoHelpers

  @impl true
  def extract_accessed_resources(repo, sql, params, _opts) do
    alias_map = EctoHelpers.parse_alias_map(sql)
    explain = "EXPLAIN QUERY PLAN " <> sql

    result =
      repo.transaction(fn ->
        case repo.query(explain, params) do
          {:ok, %{rows: rows}} -> parse_explain_rows(rows, alias_map)
          {:error, err} -> repo.rollback(format_error(err))
        end
      end)

    case result do
      {:ok, relations} -> {:ok, relations}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_explain_rows(rows, alias_map) do
    rows
    |> Enum.map(fn row -> Enum.join(row, " ") end)
    |> Enum.flat_map(&extract_relations_from_text/1)
    |> Enum.map(&EctoHelpers.resolve_alias(&1, alias_map))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&{nil, &1})
    |> MapSet.new()
  end

  defp extract_relations_from_text(text) do
    cond do
      Regex.match?(
        ~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)\s+AS\s+("[^"]+"|[A-Za-z0-9_]+)/,
        text
      ) ->
        for [_, base, _alias] <-
              Regex.scan(
                ~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)\s+AS\s+("[^"]+"|[A-Za-z0-9_]+)/,
                text
              ) do
          EctoHelpers.normalize_ident(base)
        end

      Regex.match?(~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)/, text) ->
        for [_, base] <-
              Regex.scan(~r/\b(?:SCAN|SEARCH)\s+TABLE\s+("[^"]+"|[A-Za-z0-9_]+)/, text) do
          EctoHelpers.normalize_ident(base)
        end

      Regex.match?(~r/\b(?:SCAN|SEARCH)\s+("[^"]+"|[A-Za-z0-9_]+)/, text) ->
        for [_, name] <- Regex.scan(~r/\b(?:SCAN|SEARCH)\s+("[^"]+"|[A-Za-z0-9_]+)/, text) do
          EctoHelpers.normalize_ident(name)
        end

      true ->
        []
    end
  end

  @impl true
  def transform_sql(sql) do
    Lotus.SQL.Transformer.transform(sql, :sqlite)
  end

  @impl true
  def db_type_to_lotus_type(db_type) do
    # SQLite has dynamic typing but uses "type affinity"
    case String.upcase(db_type) do
      "INTEGER" ->
        :integer

      "REAL" ->
        :float

      "NUMERIC" ->
        :decimal

      "DATE" ->
        :date

      "DATETIME" ->
        :datetime

      "BLOB" ->
        :binary

      # SQLite stores UUIDs as TEXT (no native UUID type)
      _ ->
        :text
    end
  end
end
