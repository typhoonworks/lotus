defmodule Lotus.Sources.Oracle do
  @moduledoc false

  @behaviour Lotus.Source

  require Logger

  alias Lotus.Sources.Default
  alias Lotus.SQL.FilterInjector
  alias Lotus.SQL.Identifier
  alias Lotus.SQL.SortInjector

  @jamdb_error Module.concat([:Jamdb, :Oracle, :Error])

  # ── Transaction / Session ────────────────────────────────────────────

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    read_only? = Keyword.get(opts, :read_only, true)
    timeout = Keyword.get(opts, :timeout, 15_000)

    repo.transaction(
      fn ->
        if read_only?, do: repo.query!("SET TRANSACTION READ ONLY")

        fun.()
      end,
      timeout: timeout
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def set_statement_timeout(_repo, _timeout_ms) do
    # Oracle does not support session-level statement timeouts via SQL.
    # Timeouts are managed at the connection level through :timeout in
    # the repo config, or through Oracle Resource Manager profiles.
    :ok
  end

  @impl true
  def set_search_path(repo, schema) when is_binary(schema) do
    Identifier.validate_search_path!(schema)
    repo.query!("ALTER SESSION SET CURRENT_SCHEMA = #{schema}")
    :ok
  end

  # ── Error handling ───────────────────────────────────────────────────

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @jamdb_error do
    message = Map.get(e, :message)

    cond do
      is_binary(message) and message != "" ->
        "Oracle Error: #{message}"

      true ->
        Exception.message(e)
    end
  end

  def format_error(other), do: Default.format_error(other)

  @impl true
  def handled_errors do
    # Jamdb.Oracle.Error may not be available at compile time, so we
    # reference it dynamically via the module attribute.
    [@jamdb_error]
  end

  # ── Identifier quoting ─────────────────────────────────────────────

  @impl true
  def quote_identifier(identifier) do
    escaped = String.replace(identifier, "\"", "\"\"")
    ~s("#{escaped}")
  end

  # ── Filter / Sort injection ──────────────────────────────────────────

  @impl true
  def apply_filters(sql, filters) do
    FilterInjector.apply(sql, filters, &quote_identifier/1)
  end

  @impl true
  def apply_sorts(sql, sorts) do
    SortInjector.apply(sql, sorts, &quote_identifier/1)
  end

  # ── Placeholders ─────────────────────────────────────────────────────

  @impl true
  # Oracle uses :1, :2, :3 style bind-variable placeholders.
  # Type casting is handled by the driver, but we add TO_* wrappers
  # where explicit conversion is needed for correct query results.
  def param_placeholder(idx, _var, :date), do: "TO_DATE(:#{idx}, 'YYYY-MM-DD')"

  def param_placeholder(idx, _var, :datetime),
    do: "TO_TIMESTAMP(:#{idx}, 'YYYY-MM-DD\"T\"HH24:MI:SS')"

  def param_placeholder(idx, _var, :time), do: ":#{idx}"
  def param_placeholder(idx, _var, :number), do: "TO_NUMBER(:#{idx})"
  def param_placeholder(idx, _var, :integer), do: "TO_NUMBER(:#{idx})"
  def param_placeholder(idx, _var, :float), do: "TO_NUMBER(:#{idx})"
  def param_placeholder(idx, _var, :decimal), do: "TO_NUMBER(:#{idx})"
  def param_placeholder(idx, _var, :boolean), do: ":#{idx}"
  def param_placeholder(idx, _var, :uuid), do: ":#{idx}"
  def param_placeholder(idx, _var, :json), do: ":#{idx}"
  def param_placeholder(idx, _var, :binary), do: ":#{idx}"
  def param_placeholder(idx, _var, :text), do: ":#{idx}"
  def param_placeholder(idx, _var, _type), do: ":#{idx}"

  @impl true
  def limit_offset_placeholders(limit_idx, offset_idx) do
    # Oracle uses :N style bind variable placeholders
    {":#{limit_idx}", ":#{offset_idx}"}
  end

  @impl true
  def wrap_paginated_sql(base_sql, limit_ph, offset_ph) do
    # Oracle 12c+ syntax: OFFSET n ROWS FETCH NEXT m ROWS ONLY
    # Note: Oracle doesn't support AS for subquery aliases
    "SELECT * FROM (" <>
      base_sql <>
      ") lotus_sub OFFSET " <> offset_ph <> " ROWS FETCH NEXT " <> limit_ph <> " ROWS ONLY"
  end

  @impl true
  def wrap_count_sql(base_sql) do
    # Oracle doesn't support AS for subquery aliases
    "SELECT COUNT(*) FROM (" <> base_sql <> ") lotus_sub"
  end

  # ── EXPLAIN PLAN ────────────────────────────────────────────────────

  @impl true
  def explain_plan(repo, sql, params, _opts) do
    # Oracle EXPLAIN PLAN approach:
    # 1. Execute EXPLAIN PLAN FOR <sql>
    # 2. Read the plan from PLAN_TABLE via DBMS_XPLAN
    explain_sql = "EXPLAIN PLAN FOR " <> sql

    case repo.query(explain_sql, params) do
      {:ok, _} ->
        case repo.query("SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', NULL, 'ALL'))") do
          {:ok, %{rows: rows}} ->
            plan_text = Enum.map_join(rows, "\n", fn [line] -> line end)
            {:ok, plan_text}

          {:error, err} ->
            {:error, format_error(err)}
        end

      {:error, err} ->
        {:error, format_error(err)}
    end
  end

  # ── Built-in deny rules ──────────────────────────────────────────────

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"

    [
      # Oracle system / internal schemas — deny all their tables
      {"SYS", ~r/.*/},
      {"SYSTEM", ~r/.*/},
      {"OUTLN", ~r/.*/},
      {"DBSNMP", ~r/.*/},
      {"CTXSYS", ~r/.*/},
      {"XDB", ~r/.*/},
      {"MDSYS", ~r/.*/},
      {"ORDSYS", ~r/.*/},
      {"ORDDATA", ~r/.*/},
      {"WMSYS", ~r/.*/},
      {"EXFSYS", ~r/.*/},
      {"DVSYS", ~r/.*/},
      {"LBACSYS", ~r/.*/},
      {"OLAPSYS", ~r/.*/},
      {"APEX_PUBLIC_USER", ~r/.*/},
      {"FLOWS_FILES", ~r/.*/},
      {"ANONYMOUS", ~r/.*/},
      {"APPQOSSYS", ~r/.*/},
      {"GSMADMIN_INTERNAL", ~r/.*/},
      {"OJVMSYS", ~r/.*/},
      {"AUDSYS", ~r/.*/},
      {"DBSFWUSER", ~r/.*/},
      {"REMOTE_SCHEDULER_AGENT", ~r/.*/},
      # Ecto migration tables (both upper and lower case for Oracle)
      {nil, ms},
      {nil, String.upcase(ms)},
      # Lotus internal tables (upper-case variants for Oracle)
      {nil, "lotus_queries"},
      {nil, "LOTUS_QUERIES"},
      {nil, "lotus_query_visualizations"},
      {nil, "LOTUS_QUERY_VISUALIZATIONS"},
      {nil, "lotus_dashboards"},
      {nil, "LOTUS_DASHBOARDS"},
      {nil, "lotus_dashboard_cards"},
      {nil, "LOTUS_DASHBOARD_CARDS"},
      {nil, "lotus_dashboard_filters"},
      {nil, "LOTUS_DASHBOARD_FILTERS"},
      {nil, "lotus_dashboard_card_filter_mappings"},
      {nil, "LOTUS_DASHBOARD_CARD_FILTER_MAPPINGS"}
    ]
  end

  @impl true
  def builtin_schema_denies(_repo) do
    [
      "SYS",
      "SYSTEM",
      "OUTLN",
      "DBSNMP",
      "CTXSYS",
      "XDB",
      "MDSYS",
      "ORDSYS",
      "ORDDATA",
      "WMSYS",
      "EXFSYS",
      "DVSYS",
      "LBACSYS",
      "OLAPSYS",
      "APEX_PUBLIC_USER",
      "FLOWS_FILES",
      "ANONYMOUS",
      "APPQOSSYS",
      "GSMADMIN_INTERNAL",
      "OJVMSYS",
      "AUDSYS",
      "DBSFWUSER",
      "REMOTE_SCHEDULER_AGENT",
      ~r/^APEX_\d/,
      ~r/^ORDS_/
    ]
  end

  @impl true
  def default_schemas(repo) do
    # Oracle's "schema" is equivalent to the connecting user.
    # Use the configured username as the default schema.
    username = repo.config()[:username]

    if username do
      [String.upcase(to_string(username))]
    else
      []
    end
  end

  # ── Schema introspection ─────────────────────────────────────────────

  @impl true
  def list_schemas(repo) do
    sql = """
    SELECT username
    FROM all_users
    WHERE oracle_maintained = 'N'
    ORDER BY username
    """

    case repo.query(sql) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [schema] -> schema end)

      {:error, _} ->
        # Fallback for Oracle versions < 12c that lack ORACLE_MAINTAINED
        fallback_list_schemas(repo)
    end
  end

  defp fallback_list_schemas(repo) do
    system_schemas = builtin_schema_denies(repo)

    exact_denies =
      system_schemas
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&"'#{&1}'")
      |> Enum.join(", ")

    sql = """
    SELECT username
    FROM all_users
    WHERE username NOT IN (#{exact_denies})
    ORDER BY username
    """

    %{rows: rows} = repo.query!(sql)

    regex_denies = Enum.filter(system_schemas, &match?(%Regex{}, &1))

    rows
    |> Enum.map(fn [schema] -> schema end)
    |> Enum.reject(fn schema ->
      Enum.any?(regex_denies, &Regex.match?(&1, schema))
    end)
  end

  @impl true
  def list_tables(repo, schemas, include_views?) do
    if schemas == [] do
      []
    else
      table_types =
        if include_views?, do: "'TABLE', 'VIEW'", else: "'TABLE'"

      # Oracle does not support array bind parameters in ALL_OBJECTS,
      # so we build an IN-list with bind variables.
      {placeholders, params} = build_in_clause(schemas)

      sql = """
      SELECT owner, object_name
      FROM all_objects
      WHERE object_type IN (#{table_types})
        AND owner IN (#{placeholders})
        AND temporary = 'N'
      ORDER BY owner, object_name
      """

      %{rows: rows} = repo.query!(sql, params)
      Enum.map(rows, fn [schema, table] -> {schema, table} end)
    end
  end

  @impl true
  def get_table_schema(repo, schema, table) do
    sql = """
    SELECT
      c.COLUMN_NAME,
      c.DATA_TYPE,
      c.CHAR_LENGTH,
      c.DATA_PRECISION,
      c.DATA_SCALE,
      c.NULLABLE,
      c.DATA_DEFAULT,
      CASE WHEN cc.CONSTRAINT_NAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
    FROM ALL_TAB_COLUMNS c
    LEFT JOIN (
      SELECT acc.OWNER, acc.TABLE_NAME, acc.COLUMN_NAME, acc.CONSTRAINT_NAME
      FROM ALL_CONS_COLUMNS acc
      JOIN ALL_CONSTRAINTS ac
        ON acc.CONSTRAINT_NAME = ac.CONSTRAINT_NAME
       AND acc.OWNER = ac.OWNER
      WHERE ac.CONSTRAINT_TYPE = 'P'
    ) cc
      ON c.OWNER = cc.OWNER
     AND c.TABLE_NAME = cc.TABLE_NAME
     AND c.COLUMN_NAME = cc.COLUMN_NAME
    WHERE c.OWNER = :1 AND c.TABLE_NAME = :2
    ORDER BY c.COLUMN_ID
    """

    %{rows: rows} = repo.query!(sql, [schema, table])

    Enum.map(rows, fn [name, type, char_len, num_prec, num_scale, nullable, default, is_pk] ->
      %{
        name: name,
        type: format_oracle_type(type, char_len, num_prec, num_scale),
        nullable: nullable == "Y",
        default: clean_default(default),
        primary_key: is_pk == 1
      }
    end)
  end

  @impl true
  def resolve_table_schema(repo, table, schemas) do
    if schemas == [] do
      nil
    else
      {placeholders, params} = build_in_clause(schemas)
      all_params = [table | params]

      sql = """
      SELECT owner
      FROM all_tables
      WHERE table_name = :1
        AND owner IN (#{shift_placeholders(placeholders, 1)})
      FETCH FIRST 1 ROWS ONLY
      """

      case repo.query(sql, all_params) do
        {:ok, %{rows: [[schema]]}} -> schema
        _ -> nil
      end
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp build_in_clause(values) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {value, idx}, {placeholders, params} ->
      {[":#{idx}" | placeholders], params ++ [value]}
    end)
    |> then(fn {placeholders, params} ->
      {placeholders |> Enum.reverse() |> Enum.join(", "), params}
    end)
  end

  defp shift_placeholders(placeholder_str, offset) do
    # Shift :1, :2, :3 → :2, :3, :4 (when offset = 1)
    Regex.replace(~r/:(\d+)/, placeholder_str, fn _, num ->
      ":#{String.to_integer(num) + offset}"
    end)
  end

  defp format_oracle_type("VARCHAR2", char_len, _, _) when not is_nil(char_len) and char_len > 0,
    do: "VARCHAR2(#{char_len})"

  defp format_oracle_type("NVARCHAR2", char_len, _, _)
       when not is_nil(char_len) and char_len > 0,
       do: "NVARCHAR2(#{char_len})"

  defp format_oracle_type("CHAR", char_len, _, _) when not is_nil(char_len) and char_len > 0,
    do: "CHAR(#{char_len})"

  defp format_oracle_type("NCHAR", char_len, _, _) when not is_nil(char_len) and char_len > 0,
    do: "NCHAR(#{char_len})"

  defp format_oracle_type("NUMBER", _, num_prec, num_scale)
       when not is_nil(num_prec) and not is_nil(num_scale) and num_scale > 0,
       do: "NUMBER(#{num_prec},#{num_scale})"

  defp format_oracle_type("NUMBER", _, num_prec, _) when not is_nil(num_prec),
    do: "NUMBER(#{num_prec})"

  defp format_oracle_type("FLOAT", _, num_prec, _) when not is_nil(num_prec),
    do: "FLOAT(#{num_prec})"

  defp format_oracle_type("RAW", char_len, _, _) when not is_nil(char_len) and char_len > 0,
    do: "RAW(#{char_len})"

  defp format_oracle_type(type, _, _, _), do: type

  defp clean_default(nil), do: nil
  defp clean_default(default) when is_binary(default), do: String.trim(default)
  defp clean_default(default), do: default
end
