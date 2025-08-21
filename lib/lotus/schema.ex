defmodule Lotus.Schema do
  @moduledoc """
  Schema introspection functionality for Lotus.

  Provides functions to list tables and inspect table schemas across
  different database adapters (PostgreSQL, SQLite, etc.).
  """

  alias Lotus.Visibility

  @doc """
  Lists all tables in the given repository.

  ## Examples

      {:ok, tables} = Lotus.Schema.list_tables(MyApp.Repo)
      # Returns ["users", "posts", "comments", ...]
      
      {:ok, tables} = Lotus.Schema.list_tables("analytics")
      # Uses the named data repo
  """
  @spec list_tables(module() | String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_tables(repo_or_name) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)

    try do
      relations =
        case repo.__adapter__() do
          Ecto.Adapters.Postgres ->
            list_postgres_tables(repo)

          Ecto.Adapters.SQLite3 ->
            list_sqlite_tables(repo)

          adapter ->
            {:error, "Unsupported adapter: #{inspect(adapter)}"}
        end

      case relations do
        {:error, _} = error ->
          error

        raw_relations ->
          # Apply visibility filtering
          filtered_relations =
            raw_relations
            |> Enum.filter(&Visibility.allowed_relation?(repo_name, &1))

          # Extract just table names for backward compatibility
          table_names = Enum.map(filtered_relations, fn {_schema, table} -> table end)
          {:ok, table_names}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Gets the schema information for a specific table.

  Returns a list of column definitions with their types and constraints.

  ## Examples

      {:ok, schema} = Lotus.Schema.get_table_schema(MyApp.Repo, "users")
      # Returns:
      # [
      #   %{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true},
      #   %{name: "name", type: "varchar", nullable: true, default: nil, primary_key: false},
      #   ...
      # ]
  """
  @spec get_table_schema(module() | String.t(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def get_table_schema(repo_or_name, table_name) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)

    # Check if table is visible before proceeding
    schema_name =
      case repo.__adapter__() do
        # Default schema for Postgres
        Ecto.Adapters.Postgres -> "public"
        # SQLite doesn't use schemas
        Ecto.Adapters.SQLite3 -> nil
        _ -> nil
      end

    if Visibility.allowed_relation?(repo_name, {schema_name, table_name}) do
      try do
        schema =
          case repo.__adapter__() do
            Ecto.Adapters.Postgres ->
              get_postgres_schema(repo, table_name)

            Ecto.Adapters.SQLite3 ->
              get_sqlite_schema(repo, table_name)

            adapter ->
              {:error, "Unsupported adapter: #{inspect(adapter)}"}
          end

        case schema do
          {:error, _} = error -> error
          result -> {:ok, result}
        end
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Table '#{table_name}' is not visible by Lotus policy"}
    end
  end

  @doc """
  Gets basic statistics about a table.

  Returns information like row count and table size.

  ## Examples

      {:ok, stats} = Lotus.Schema.get_table_stats(MyApp.Repo, "users")
      # Returns:
      # %{row_count: 1234, size_bytes: 524288}
  """
  @spec get_table_stats(module() | String.t(), String.t()) ::
          {:ok, %{row_count: non_neg_integer()}} | {:error, binary()}
  def get_table_stats(repo_or_name, table_name) do
    repo = resolve_repo(repo_or_name)
    repo_name = resolve_repo_name(repo_or_name)

    # Check if table is visible before proceeding
    schema_name =
      case repo.__adapter__() do
        # Default schema for Postgres
        Ecto.Adapters.Postgres -> "public"
        # SQLite doesn't use schemas
        Ecto.Adapters.SQLite3 -> nil
        _ -> nil
      end

    if Visibility.allowed_relation?(repo_name, {schema_name, table_name}) do
      try do
        query = "SELECT COUNT(*) as count FROM #{table_name}"
        result = repo.query!(query)

        count =
          case result.rows do
            [[count]] -> count
            _ -> 0
          end

        {:ok, %{row_count: count}}
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Table '#{table_name}' is not visible by Lotus policy"}
    end
  end

  # Private functions

  defp resolve_repo(repo_module) when is_atom(repo_module), do: repo_module

  defp resolve_repo(repo_name) when is_binary(repo_name) do
    Lotus.Config.get_data_repo!(repo_name)
  end

  defp resolve_repo_name(repo_name) when is_binary(repo_name), do: repo_name

  defp resolve_repo_name(repo_module) when is_atom(repo_module) do
    # Reverse lookup: find repo name from module
    Lotus.Config.data_repos()
    |> Enum.find_value(fn {name, mod} ->
      if mod == repo_module, do: name
    end) || "default"
  end

  defp list_postgres_tables(repo) do
    query = """
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
    ORDER BY table_name
    """

    result = repo.query!(query)

    result.rows
    |> Enum.map(fn [schema, table_name] -> {schema, table_name} end)
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

  defp get_postgres_schema(repo, table_name) do
    query = """
    SELECT 
      c.column_name,
      c.data_type,
      c.character_maximum_length,
      c.numeric_precision,
      c.numeric_scale,
      c.is_nullable,
      c.column_default,
      CASE 
        WHEN tc.constraint_type = 'PRIMARY KEY' THEN true
        ELSE false
      END as is_primary_key
    FROM information_schema.columns c
    LEFT JOIN information_schema.key_column_usage kcu
      ON c.table_name = kcu.table_name 
      AND c.column_name = kcu.column_name
      AND c.table_schema = kcu.table_schema
    LEFT JOIN information_schema.table_constraints tc
      ON kcu.constraint_name = tc.constraint_name
      AND kcu.table_schema = tc.table_schema
      AND tc.constraint_type = 'PRIMARY KEY'
    WHERE c.table_schema = 'public'
      AND c.table_name = $1
    ORDER BY c.ordinal_position
    """

    result = repo.query!(query, [table_name])

    Enum.map(result.rows, fn row ->
      [name, type, char_len, num_prec, num_scale, nullable, default, is_pk] = row

      # Format type with precision/length
      formatted_type = format_postgres_type(type, char_len, num_prec, num_scale)

      %{
        name: name,
        type: formatted_type,
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
