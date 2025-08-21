defmodule Lotus.Schema do
  @moduledoc """
  Schema introspection functionality for Lotus.

  Provides functions to list tables and inspect table schemas across
  different database adapters (PostgreSQL, SQLite, etc.).
  """

  alias Lotus.Visibility

  @doc """
  Lists all tables in the given repository.

  For databases with schemas (like PostgreSQL), returns {schema, table} tuples.
  For databases without schemas (like SQLite), returns just table names as strings.

  ## Options

  - `:schema` - Search in specific schema (e.g., `schema: "reporting"`)
  - `:schemas` - Search in multiple schemas (e.g., `schemas: ["reporting", "public"]`)
  - `:search_path` - Use PostgreSQL search_path (e.g., `search_path: "reporting, public"`)
  - `:include_views` - Include views in results (default: false)

  ## Examples

      {:ok, tables} = Lotus.Schema.list_tables(MyApp.Repo)
      # PostgreSQL: [{"public", "users"}, {"public", "posts"}, ...]

      {:ok, tables} = Lotus.Schema.list_tables("postgres", search_path: "reporting, public")
      # PostgreSQL: [{"reporting", "customers"}, {"reporting", "orders"}, {"public", "users"}, ...]

      {:ok, tables} = Lotus.Schema.list_tables("sqlite")
      # SQLite: ["products", "orders", "order_items"]
  """
  @spec list_tables(module() | String.t(), keyword()) ::
          {:ok, [{String.t(), String.t()}] | [String.t()]} | {:error, term()}
  def list_tables(repo_or_name, opts \\ []) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)
    schemas = effective_schemas(repo, opts)
    include_views? = Keyword.get(opts, :include_views, false)

    try do
      relations =
        case repo.__adapter__() do
          Ecto.Adapters.Postgres ->
            list_postgres_tables(repo, schemas, include_views?)

          Ecto.Adapters.SQLite3 ->
            list_sqlite_tables(repo)

          adapter ->
            {:error, "Unsupported adapter: #{inspect(adapter)}"}
        end

      case relations do
        {:error, _} = error ->
          error

        raw_relations ->
          filtered_relations =
            raw_relations
            |> Enum.filter(&Visibility.allowed_relation?(repo_name, &1))

          case repo.__adapter__() do
            Ecto.Adapters.Postgres ->
              {:ok, filtered_relations}

            _ ->
              table_names = Enum.map(filtered_relations, fn {nil, table} -> table end)
              {:ok, table_names}
          end
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Gets the schema information for a specific table.

  Returns a list of column definitions with their types and constraints.

  ## Options

  - `:schema` - Look for table in specific schema
  - `:schemas` - Search for table in multiple schemas (first match wins)
  - `:search_path` - Use PostgreSQL search_path to resolve table location

  ## Examples

      {:ok, schema} = Lotus.Schema.get_table_schema(MyApp.Repo, "users")
      # Returns schema for public.users

      {:ok, schema} = Lotus.Schema.get_table_schema("postgres", "customers", schema: "reporting")
      # Returns schema for reporting.customers

      {:ok, schema} = Lotus.Schema.get_table_schema("postgres", "customers", search_path: "reporting, public")
      # Finds customers table using search_path resolution
  """
  @spec get_table_schema(module() | String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_table_schema(repo_or_name, table_name, opts \\ []) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)
    schemas = effective_schemas(repo, opts)

    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        case resolve_pg_table_schema(repo, table_name, schemas) do
          nil ->
            {:error, "Table '#{table_name}' not found in schemas: #{Enum.join(schemas, ", ")}"}

          schema ->
            if Visibility.allowed_relation?(repo_name, {schema, table_name}) do
              try do
                {:ok, get_postgres_schema(repo, schema, table_name)}
              rescue
                e -> {:error, Exception.message(e)}
              end
            else
              {:error, "Table '#{schema}.#{table_name}' is not visible by Lotus policy"}
            end
        end

      Ecto.Adapters.SQLite3 ->
        if Visibility.allowed_relation?(repo_name, {nil, table_name}) do
          try do
            {:ok, get_sqlite_schema(repo, table_name)}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, "Table '#{table_name}' is not visible by Lotus policy"}
        end

      adapter ->
        {:error, "Unsupported adapter: #{inspect(adapter)}"}
    end
  end

  @doc """
  Gets basic statistics about a table.

  Returns information like row count and table size.

  ## Options

  - `:schema` - Look for table in specific schema
  - `:schemas` - Search for table in multiple schemas (first match wins)
  - `:search_path` - Use PostgreSQL search_path to resolve table location

  ## Examples

      {:ok, stats} = Lotus.Schema.get_table_stats(MyApp.Repo, "users")
      # Returns: %{row_count: 1234}

      {:ok, stats} = Lotus.Schema.get_table_stats("postgres", "customers", schema: "reporting")
      # Gets stats for reporting.customers
  """
  @spec get_table_stats(module() | String.t(), String.t(), keyword()) ::
          {:ok, %{row_count: non_neg_integer()}} | {:error, binary()}
  def get_table_stats(repo_or_name, table_name, opts \\ []) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)

    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        schemas = effective_schemas(repo, opts)

        case resolve_pg_table_schema(repo, table_name, schemas) do
          nil ->
            {:error, "Table '#{table_name}' not found in schemas: #{Enum.join(schemas, ", ")}"}

          schema ->
            if Visibility.allowed_relation?(repo_name, {schema, table_name}) do
              try do
                qt = ~s|"#{String.replace(table_name, ~s|"|, ~s|""|)}"|
                qs = ~s|"#{String.replace(schema, ~s|"|, ~s|""|)}"|
                %{rows: [[count]]} = repo.query!("SELECT COUNT(*) FROM #{qs}.#{qt}")
                {:ok, %{row_count: count}}
              rescue
                e -> {:error, Exception.message(e)}
              end
            else
              {:error, "Table '#{schema}.#{table_name}' is not visible by Lotus policy"}
            end
        end

      Ecto.Adapters.SQLite3 ->
        if Visibility.allowed_relation?(repo_name, {nil, table_name}) do
          try do
            %{rows: [[count]]} = repo.query!("SELECT COUNT(*) FROM #{table_name}")
            {:ok, %{row_count: count}}
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, "Table '#{table_name}' is not visible by Lotus policy"}
        end

      adapter ->
        {:error, "Unsupported adapter: #{inspect(adapter)}"}
    end
  end

  @doc """
  Lists all relations (tables with schema information) in the given repository.

  Similar to list_tables/2 but returns {schema, table} tuples instead of just table names.
  Useful for UIs that need to display schema information.

  ## Examples

      {:ok, relations} = Lotus.Schema.list_relations("postgres", search_path: "reporting, public")
      # Returns [{"reporting", "customers"}, {"reporting", "orders"}, {"public", "users"}, ...]
  """
  @spec list_relations(module() | String.t(), keyword()) ::
          {:ok, [{String.t() | nil, String.t()}]} | {:error, term()}
  def list_relations(repo_or_name, opts \\ []) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)
    schemas = effective_schemas(repo, opts)
    include_views? = Keyword.get(opts, :include_views, false)

    try do
      relations =
        case repo.__adapter__() do
          Ecto.Adapters.Postgres ->
            list_postgres_tables(repo, schemas, include_views?)

          Ecto.Adapters.SQLite3 ->
            list_sqlite_tables(repo)

          adapter ->
            {:error, "Unsupported adapter: #{inspect(adapter)}"}
        end

      case relations do
        {:error, _} = error ->
          error

        raw_relations ->
          filtered_relations =
            raw_relations
            |> Enum.filter(&Visibility.allowed_relation?(repo_name, &1))

          {:ok, filtered_relations}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp effective_schemas(repo, opts) do
    schemas =
      cond do
        is_binary(Keyword.get(opts, :schema)) ->
          [Keyword.fetch!(opts, :schema)]

        is_list(Keyword.get(opts, :schemas)) ->
          Keyword.fetch!(opts, :schemas)

        is_binary(Keyword.get(opts, :search_path)) ->
          parse_search_path(Keyword.fetch!(opts, :search_path))

        sp = get_in(repo.config(), [:parameters, :search_path]) ->
          parse_search_path(sp)

        true ->
          ["public"]
      end
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 == "$user"))

    if schemas == [], do: ["public"], else: schemas
  end

  defp parse_search_path(sp) when is_binary(sp),
    do: sp |> String.split(",") |> Enum.map(&String.trim/1)

  defp resolve_pg_table_schema(repo, table, schemas) do
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

  defp resolve_repo(repo_module) when is_atom(repo_module), do: repo_module

  defp resolve_repo(repo_name) when is_binary(repo_name) do
    Lotus.Config.get_data_repo!(repo_name)
  end

  defp resolve_repo_name(repo_name) when is_binary(repo_name), do: repo_name

  defp resolve_repo_name(repo_module) when is_atom(repo_module) do
    Lotus.Config.data_repos()
    |> Enum.find_value(fn {name, mod} ->
      if mod == repo_module, do: name
    end) || "default"
  end

  defp list_postgres_tables(repo, schemas, include_views?) do
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

  defp list_sqlite_tables(repo) do
    query = """
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name NOT LIKE 'sqlite_%'
    ORDER BY name
    """

    result = repo.query!(query)

    result.rows
    |> Enum.map(fn [table_name] -> {nil, table_name} end)
  end

  defp get_postgres_schema(repo, schema, table) do
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

  defp get_sqlite_schema(repo, table_name) do
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
