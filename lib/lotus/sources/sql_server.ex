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

  @impl true
  def param_placeholder(idx, _var, _type), do: "@#{idx}"

  @impl true
  def limit_offset_placeholders(limit_idx, offset_idx) do
    {"@#{limit_idx}", "@#{offset_idx}"}
  end

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"
    prefix = repo.config()[:migration_default_prefix] || "dbo"

    [
      {"sys", ~r/.*/},
      {"INFORMATION_SCHEMA", ~r/.*/},
      {prefix, ms},
      {prefix, "lotus_queries"},
      {prefix, "lotus_query_visualizations"},
      {prefix, "lotus_dashboards"},
      {prefix, "lotus_dashboard_cards"},
      {prefix, "lotus_dashboard_filters"},
      {prefix, "lotus_dashboard_card_filter_mappings"}
    ]
  end

  @impl true
  def default_schemas(_repo) do
    ["dbo"]
  end

  @impl true
  def builtin_schema_denies(_repo) do
    [
      "sys",
      "INFORMATION_SCHEMA",
      "guest",
      "db_owner",
      "db_accessadmin",
      "db_backupoperator",
      "db_datareader",
      "db_datawriter",
      "db_ddladmin",
      "db_denydatareader",
      "db_denydatawriter",
      "db_securityadmin",
      ~r/^db_/,
      ~r/^##/,
      ~r/^#/
    ]
  end

  @impl true
  def list_schemas(repo) do
    sql = """
      SELECT name AS [Username]
      FROM sys.database_principals
      WHERE type NOT IN ('A', 'G', 'R', 'X')
        AND sid IS NOT NULL 
        AND name NOT IN ('guest', 'dbo', 'INFORMATION_SCHEMA', 'sys')
      ORDER BY [Username];
    """

    %{rows: rows} = repo.query!(sql)
    Enum.map(rows, fn [schema] -> schema end)
  end

  @impl true
  def list_tables(repo, schemas, include_views?) do
    types_sql =
      if include_views?, do: "'U','V'", else: "'U'"

    placeholders =
      schemas
      |> Enum.with_index(1)
      |> Enum.map(fn {_, idx} -> "@p#{idx}" end)
      |> Enum.join(", ")

    sql = """
    SELECT s.name AS schema_name, o.name AS table_name
    FROM sys.objects o
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE o.type IN (#{types_sql})
      AND s.name IN (#{placeholders})
    ORDER BY s.name, o.name
    """

    %{rows: rows} = repo.query!(sql, schemas)
    Enum.map(rows, fn [schema, table] -> {schema, table} end)
  end

  @impl true
  def get_table_schema(repo, schema, table) do
    sql = """
    SELECT
      c.name AS column_name,
      t.name AS data_type,
      c.max_length,
      c.precision,
      c.scale,
      c.is_nullable,
      dc.definition AS column_default,
      CASE WHEN ic.column_id IS NOT NULL THEN 1 ELSE 0 END AS is_primary_key
    FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    INNER JOIN sys.objects o ON c.object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
    LEFT JOIN sys.index_columns ic ON ic.object_id = c.object_id 
      AND ic.column_id = c.column_id
    LEFT JOIN sys.indexes i ON ic.object_id = i.object_id 
      AND ic.index_id = i.index_id 
      AND i.is_primary_key = 1
    WHERE s.name = @1 AND o.name = @2
    ORDER BY c.column_id
    """

    %{rows: rows} = repo.query!(sql, [schema, table])

    Enum.map(rows, fn [name, type, max_len, num_prec, num_scale, nullable, default, is_pk] ->
      %{
        name: name,
        type: format_mssql_type(type, max_len, num_prec, num_scale),
        nullable: nullable == 1,
        default: default,
        primary_key: is_pk == 1
      }
    end)
  end

  @impl true
  def resolve_table_schema(repo, table, schemas) do
    schema_placeholders =
      schemas
      |> Enum.with_index(2)
      |> Enum.map(fn {_, idx} -> "@#{idx}" end)
      |> Enum.join(", ")

    order_case =
      schemas
      |> Enum.with_index(2)
      |> Enum.map(fn {_, idx} -> "WHEN s.name = @#{idx} THEN #{idx - 1}" end)
      |> Enum.join(" ")

    sql = """
    SELECT TOP 1 s.name
    FROM sys.objects o
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE o.name = @p1 
      AND o.type IN ('U', 'V')
      AND s.name IN (#{schema_placeholders})
    ORDER BY CASE #{order_case} END
    """

    params = [table | schemas]

    case repo.query(sql, params) do
      {:ok, %{rows: [[schema]]}} -> schema
      _ -> nil
    end
  end

  defp format_mssql_type("nvarchar", char_len, _, _) when not is_nil(char_len),
    do: "nvarchar(#{char_len})"

  defp format_mssql_type("char", char_len, _, _) when not is_nil(char_len),
    do: "char(#{char_len})"

  defp format_mssql_type("numberic", _, num_prec, num_scale)
       when not is_nil(num_prec) and not is_nil(num_scale),
       do: "decimal(#{num_prec},#{num_scale})"

  defp format_mssql_type("decimal", _, num_prec, _) when not is_nil(num_prec),
    do: "decimal(#{num_prec})"

  defp format_mssql_type(type, _, _, _), do: type
end
