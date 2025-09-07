defmodule Lotus.Sources.Postgres do
  @moduledoc false

  @behaviour Lotus.Source

  @postgrex_error Module.concat([:Postgrex, :Error])

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    read_only? = Keyword.get(opts, :read_only, true)
    stmt_ms = Keyword.get(opts, :statement_timeout_ms, 5_000)
    timeout = Keyword.get(opts, :timeout, 15_000)
    search_path = Keyword.get(opts, :search_path)

    repo.transaction(
      fn ->
        if read_only?, do: repo.query!("SET LOCAL transaction_read_only = on")
        repo.query!("SET LOCAL statement_timeout = #{stmt_ms}")
        if search_path, do: repo.query!("SET LOCAL search_path = #{search_path}")

        fun.()
      end,
      timeout: timeout
    )
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def set_statement_timeout(repo, timeout_ms) do
    repo.query!("SET LOCAL statement_timeout = #{timeout_ms}")
    :ok
  end

  @impl true
  def set_search_path(repo, search_path) when is_binary(search_path) do
    repo.query!("SET LOCAL search_path = #{search_path}")
    :ok
  end

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @postgrex_error do
    pg = Map.get(e, :postgres)

    cond do
      is_map(pg) and pg[:code] == :syntax_error and is_binary(pg[:message]) ->
        "SQL syntax error: #{pg[:message]}"

      is_map(pg) and is_binary(pg[:message]) ->
        "SQL error: #{pg[:message]}"

      is_binary(Map.get(e, :message)) ->
        "SQL error: #{Map.get(e, :message)}"

      true ->
        Exception.message(e)
    end
  end

  def format_error(other), do: Lotus.Sources.Default.format_error(other)

  @impl true
  def param_placeholder(idx, _var, :date), do: "$#{idx}::date"
  def param_placeholder(idx, _var, :datetime), do: "$#{idx}::timestamp"
  def param_placeholder(idx, _var, :time), do: "$#{idx}::time"
  def param_placeholder(idx, _var, :number), do: "$#{idx}::numeric"
  def param_placeholder(idx, _var, :integer), do: "$#{idx}::integer"
  def param_placeholder(idx, _var, :boolean), do: "$#{idx}::boolean"
  def param_placeholder(idx, _var, :json), do: "$#{idx}::jsonb"
  def param_placeholder(idx, _var, _type), do: "$#{idx}"

  @impl true
  def limit_offset_placeholders(limit_idx, offset_idx) do
    # Postgres supports positional parameters for LIMIT/OFFSET
    {"$#{limit_idx}", "$#{offset_idx}"}
  end

  @impl true
  def handled_errors, do: [Postgrex.Error]

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"
    prefix = repo.config()[:migration_default_prefix] || "public"

    [
      {"pg_catalog", ~r/.*/},
      {"information_schema", ~r/.*/},
      {prefix, ms},
      {prefix, "lotus_queries"}
    ]
  end

  @impl true
  def default_schemas(_repo) do
    ["public"]
  end

  @impl true
  def builtin_schema_denies(_repo) do
    [
      "auth",
      "extensions",
      "graphql",
      "graphql_public",
      "pgbouncer",
      "realtime",
      "storage",
      "vault",
      "pg_catalog",
      "information_schema",
      "pg_toast",
      ~r/^pg_temp/,
      ~r/^pg_toast/
    ]
  end

  @impl true
  def list_schemas(repo) do
    sql = """
    SELECT schema_name
    FROM information_schema.schemata
    WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    ORDER BY schema_name
    """

    %{rows: rows} = repo.query!(sql)
    Enum.map(rows, fn [schema] -> schema end)
  end

  @impl true
  def list_tables(repo, schemas, include_views?) do
    types_sql =
      if include_views?, do: "'BASE TABLE','VIEW'", else: "'BASE TABLE'"

    sql = """
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_type IN (#{types_sql})
      AND table_schema = ANY($1::text[])
    ORDER BY table_schema, table_name
    """

    %{rows: rows} = repo.query!(sql, [schemas])
    Enum.map(rows, fn [schema, table] -> {schema, table} end)
  end

  @impl true
  def get_table_schema(repo, schema, table) do
    sql = """
    SELECT
      c.column_name,
      c.data_type,
      c.character_maximum_length,
      c.numeric_precision,
      c.numeric_scale,
      c.is_nullable,
      c.column_default,
      CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN true ELSE false END as is_primary_key
    FROM information_schema.columns c
    LEFT JOIN information_schema.key_column_usage kcu
      ON c.table_name = kcu.table_name
     AND c.column_name = kcu.column_name
     AND c.table_schema = kcu.table_schema
    LEFT JOIN information_schema.table_constraints tc
      ON kcu.constraint_name = tc.constraint_name
     AND kcu.table_schema = tc.table_schema
     AND tc.constraint_type = 'PRIMARY KEY'
    WHERE c.table_schema = $1 AND c.table_name = $2
    ORDER BY c.ordinal_position
    """

    %{rows: rows} = repo.query!(sql, [schema, table])

    Enum.map(rows, fn [name, type, char_len, num_prec, num_scale, nullable, default, is_pk] ->
      %{
        name: name,
        type: format_postgres_type(type, char_len, num_prec, num_scale),
        nullable: nullable == "YES",
        default: default,
        primary_key: is_pk || false
      }
    end)
  end

  @impl true
  def resolve_table_schema(repo, table, schemas) do
    sql = """
    SELECT table_schema
    FROM information_schema.tables
    WHERE table_name = $1 AND table_schema = ANY($2::text[])
    ORDER BY array_position($2::text[], table_schema) NULLS LAST
    LIMIT 1
    """

    case repo.query(sql, [table, schemas]) do
      {:ok, %{rows: [[schema]]}} -> schema
      _ -> nil
    end
  end

  defp format_postgres_type(type, char_len, num_prec, num_scale) do
    cond do
      type in ["character varying", "varchar"] && char_len ->
        "varchar(#{char_len})"

      type == "character" && char_len ->
        "char(#{char_len})"

      type == "numeric" && num_prec && num_scale ->
        "numeric(#{num_prec},#{num_scale})"

      type == "numeric" && num_prec ->
        "numeric(#{num_prec})"

      true ->
        type
    end
  end
end
