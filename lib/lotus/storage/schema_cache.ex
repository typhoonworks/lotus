defmodule Lotus.Storage.SchemaCache do
  @moduledoc """
  Caches table schema metadata for automatic type detection and casting.

  Maintains in-memory representation of database schema.
  Uses Lotus's existing ETS-based cache infrastructure to store table/column metadata
  and avoid repeated `information_schema` queries.

  ## Features

  - **Table-level caching**: Caches all columns for a table together for efficiency
  - **TTL-based expiration**: Default 5-minute TTL (configurable)
  - **Graceful degradation**: Falls back to direct schema query if cache unavailable
  - **Warm cache support**: Preload frequently-used tables on application startup

  ## Usage

      # Get all columns for a table
      {:ok, schema} = SchemaCache.get_table_schema(MyApp.Repo, "public", "users")
      # => %{"id" => %{type: "uuid", nullable: false, ...}, ...}

      # Get specific column type
      {:ok, type} = SchemaCache.get_column_type(MyApp.Repo, "public", "users", "id")
      # => "uuid"

      # Invalidate cache after migrations
      SchemaCache.invalidate(MyApp.Repo, "public", "users")
  """

  require Logger

  @type column_info :: %{
          type: String.t(),
          nullable: boolean(),
          default: term() | nil,
          primary_key: boolean()
        }

  @default_ttl_ms :timer.minutes(5)

  @doc """
  Get column metadata for a table. Returns map of column_name => column_info.
  Caches result for subsequent calls.

  ## Examples

      {:ok, schema} = SchemaCache.get_table_schema(MyApp.Repo, "public", "users")
      schema["id"]
      # => %{type: "uuid", nullable: false, default: nil, primary_key: true}
  """
  @spec get_table_schema(
          repo :: module(),
          schema :: String.t() | nil,
          table :: String.t()
        ) :: {:ok, %{String.t() => column_info()}} | {:error, term()}
  def get_table_schema(repo, schema, table) do
    cache_key = cache_key(repo, schema, table)
    ttl_ms = get_ttl_ms()

    try do
      case Lotus.Cache.get_or_store(cache_key, ttl_ms, fn ->
             fetch_schema_from_db(repo, schema, table)
           end) do
        {:ok, schema_map, _cache_status} ->
          {:ok, schema_map}

        {:error, reason} ->
          Logger.warning(
            "Failed to get/cache schema for #{inspect(repo)}.#{schema}.#{table}: #{inspect(reason)}"
          )

          # Fallback to direct fetch if cache fails
          {:ok, fetch_schema_from_db(repo, schema, table)}
      end
    rescue
      error in [ArgumentError, DBConnection.ConnectionError, Ecto.QueryError] ->
        {:error, Exception.message(error)}
    end
  end

  @doc """
  Get specific column type. Returns the database-native type string.

  ## Examples

      {:ok, type} = SchemaCache.get_column_type(MyApp.Repo, "public", "users", "id")
      # => "uuid"

      SchemaCache.get_column_type(MyApp.Repo, "public", "users", "nonexistent")
      # => :not_found
  """
  @spec get_column_type(
          repo :: module(),
          schema :: String.t() | nil,
          table :: String.t(),
          column :: String.t()
        ) :: {:ok, String.t()} | :not_found
  def get_column_type(repo, schema, table, column) do
    case get_table_schema(repo, schema, table) do
      {:ok, table_schema} ->
        case Map.get(table_schema, column) do
          nil -> :not_found
          column_info -> {:ok, column_info.type}
        end

      {:error, _reason} ->
        :not_found
    end
  end

  @doc """
  Invalidate cache for a specific table (useful after migrations).

  ## Examples

      SchemaCache.invalidate(MyApp.Repo, "public", "users")
      # => :ok
  """
  @spec invalidate(repo :: module(), schema :: String.t() | nil, table :: String.t()) :: :ok
  def invalidate(repo, schema, table) do
    cache_key = cache_key(repo, schema, table)
    Lotus.Cache.delete(cache_key)
    :ok
  end

  @doc """
  Warm cache with frequently-used tables on application startup.

  ## Examples

      SchemaCache.warm_cache(MyApp.Repo, [
        {"public", "users"},
        {"public", "orders"}
      ])
      # => :ok
  """
  @spec warm_cache(
          repo :: module(),
          tables :: [{schema :: String.t() | nil, table :: String.t()}]
        ) :: :ok
  def warm_cache(repo, tables) do
    Enum.each(tables, fn {schema, table} ->
      case get_table_schema(repo, schema, table) do
        {:ok, _} ->
          Logger.debug("Warmed schema cache for #{inspect(repo)}.#{schema}.#{table}")

        {:error, reason} ->
          Logger.warning(
            "Failed to warm schema cache for #{inspect(repo)}.#{schema}.#{table}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  defp cache_key(repo, schema, table) do
    repo_name = repo |> Module.split() |> List.last()
    schema_part = if schema, do: ":#{schema}", else: ""
    "schema_cache:#{repo_name}#{schema_part}:#{table}"
  end

  defp fetch_schema_from_db(repo, schema, table) do
    columns = Lotus.Source.get_table_schema(repo, schema, table)

    Enum.into(columns, %{}, fn column ->
      {column.name, Map.take(column, [:type, :nullable, :default, :primary_key])}
    end)
  rescue
    error in [ArgumentError, DBConnection.ConnectionError, Ecto.QueryError] ->
      Logger.error(
        "Failed to fetch schema for #{inspect(repo)}.#{schema}.#{table}: #{Exception.message(error)}"
      )

      reraise error, __STACKTRACE__
  end

  defp get_ttl_ms do
    Application.get_env(:lotus, :schema_cache, [])
    |> Keyword.get(:ttl_ms, @default_ttl_ms)
  end
end
