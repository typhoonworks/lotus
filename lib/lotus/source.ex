defmodule Lotus.Source do
  @moduledoc """
  Public facade for data sources in Lotus.

  Provides convenience functions for resolving, listing, and querying data
  sources. All functions accept `%Adapter{}` structs, source name strings,
  or raw repo modules, resolving lazily as needed.
  """

  alias Lotus.Config
  alias Lotus.Source.Adapter

  # ---------------------------------------------------------------------------
  # Resolution
  # ---------------------------------------------------------------------------

  @doc """
  Resolve to an `%Adapter{}` struct.

  Accepts:
    * `source_opt` — configured name (string) or source module (atom) or nil
    * `q_source`   — query's stored source (string or module) or nil

  Falls back to the default source. Raises on resolution failure.
  """
  @spec resolve!(nil | String.t() | module(), nil | String.t() | module()) :: Adapter.t()
  def resolve!(source_opt, q_source) do
    case resolver().resolve(source_opt, q_source) do
      {:ok, %Adapter{} = adapter} ->
        adapter

      {:error, :not_found} ->
        available = resolver().list_source_names()
        label = source_opt || q_source

        raise ArgumentError,
              "Data source '#{label}' not configured. " <>
                "Available sources: #{inspect(available)}"
    end
  end

  @doc """
  Lists all configured source adapters.
  """
  @spec list_sources() :: [Adapter.t()]
  def list_sources, do: resolver().list_sources()

  @doc """
  Gets a source adapter by name. Raises if not found.
  """
  @spec get_source!(String.t()) :: Adapter.t()
  def get_source!(name), do: resolver().get_source!(name)

  @doc """
  Returns the default source as an `%Adapter{}` struct.
  """
  @spec default_source() :: Adapter.t()
  def default_source do
    {_name, adapter} = resolver().default_source()
    adapter
  end

  @doc false
  @spec name_from_module!(module()) :: String.t()
  def name_from_module!(mod) do
    case Enum.find(Config.data_sources(), fn {_name, m} -> m == mod end) do
      {name, _} ->
        name

      nil ->
        raise ArgumentError,
              "Source module #{inspect(mod)} isn't in :lotus, :data_sources. " <>
                "Configured names: #{inspect(Map.keys(Config.data_sources()))}"
    end
  end

  # ---------------------------------------------------------------------------
  # Source identity
  # ---------------------------------------------------------------------------

  @doc """
  Detect the source type from an adapter, repository module, or name.
  """
  @spec source_type(Adapter.t() | module() | String.t()) :: Adapter.source_type()
  def source_type(%Adapter{source_type: st}), do: st

  def source_type(repo_or_name) when is_binary(repo_or_name) or is_atom(repo_or_name) do
    resolve!(repo_or_name, nil).source_type
  end

  @doc """
  Whether a source supports a specific feature.

  Accepts an `%Adapter{}` struct or a source name/repo module (resolved to adapter).
  """
  @spec supports_feature?(Adapter.t() | String.t() | module(), atom()) :: boolean()
  def supports_feature?(%Adapter{} = adapter, feature) do
    Adapter.supports_feature?(adapter, feature)
  end

  def supports_feature?(source, feature) when is_binary(source) or is_atom(source) do
    resolve!(source, nil) |> Adapter.supports_feature?(feature)
  end

  @doc """
  Return the human-readable label for the top-level hierarchy in a source.
  """
  @spec hierarchy_label(Adapter.t() | String.t()) :: String.t()
  def hierarchy_label(%Adapter{} = adapter), do: Adapter.hierarchy_label(adapter)

  def hierarchy_label(source_name) when is_binary(source_name) do
    source_name |> get_source!() |> Adapter.hierarchy_label()
  end

  @doc """
  Return an example query string suitable for placeholder text.
  """
  @spec example_query(Adapter.t() | String.t(), String.t(), String.t() | nil) :: String.t()
  def example_query(%Adapter{} = adapter, table, schema),
    do: Adapter.example_query(adapter, table, schema)

  def example_query(source_name, table, schema) when is_binary(source_name) do
    source_name |> get_source!() |> Adapter.example_query(table, schema)
  end

  @doc """
  Return the query language identifier for a source.
  """
  @spec query_language(Adapter.t() | String.t()) :: String.t()
  def query_language(%Adapter{} = adapter), do: Adapter.query_language(adapter)

  def query_language(source_name) when is_binary(source_name) do
    source_name |> get_source!() |> Adapter.query_language()
  end

  @doc """
  Wrap a statement with a limit clause using the source's syntax.
  """
  @spec limit_query(Adapter.t() | String.t(), String.t(), pos_integer()) :: String.t()
  def limit_query(%Adapter{} = adapter, statement, limit),
    do: Adapter.limit_query(adapter, statement, limit)

  def limit_query(source_name, statement, limit) when is_binary(source_name) do
    source_name |> get_source!() |> Adapter.limit_query(statement, limit)
  end

  # ---------------------------------------------------------------------------
  # Deprecated dispatch functions (to be removed once all callers migrate)
  # ---------------------------------------------------------------------------

  @doc false
  def execute_in_transaction(repo, fun, opts \\ []) do
    dialect_for(repo).execute_in_transaction(repo, fun, opts)
  end

  @doc false
  def set_statement_timeout(repo, ms), do: dialect_for(repo).set_statement_timeout(repo, ms)

  @doc false
  def set_search_path(repo, path) when is_binary(path),
    do: dialect_for(repo).set_search_path(repo, path)

  def set_search_path(_, _), do: :ok

  @doc false
  def builtin_denies(repo), do: dialect_for(repo).builtin_denies(repo)

  @doc false
  def builtin_schema_denies(repo), do: dialect_for(repo).builtin_schema_denies(repo)

  @doc false
  def default_schemas(repo), do: dialect_for(repo).default_schemas(repo)

  @doc false
  def format_error(error), do: dialect_for_error(error).format_error(error)

  @doc false
  def param_placeholder(repo_or_name, index, var, type) when is_integer(index) and index > 0 do
    dialect_for(resolve_repo!(repo_or_name)).param_placeholder(index, var, type)
  end

  @doc false
  def limit_offset_placeholders(repo_or_name, limit_index, offset_index)
      when is_integer(limit_index) and limit_index > 0 and is_integer(offset_index) and
             offset_index > 0 do
    dialect_for(resolve_repo!(repo_or_name)).limit_offset_placeholders(limit_index, offset_index)
  end

  @doc false
  def list_schemas(repo), do: dialect_for(repo).list_schemas(repo)

  @doc false
  def list_tables(repo, schemas, include_views? \\ false),
    do: dialect_for(repo).list_tables(repo, schemas, include_views?)

  @doc false
  def get_table_schema(repo, schema, table),
    do: dialect_for(repo).get_table_schema(repo, schema, table)

  @doc false
  def resolve_table_schema(repo, table, schemas),
    do: dialect_for(repo).resolve_table_schema(repo, table, schemas)

  @doc false
  def explain_plan(repo, sql, params \\ [], opts \\ []),
    do: dialect_for(repo).explain_plan(repo, sql, params, opts)

  @doc false
  def quote_identifier(repo_or_name, identifier),
    do: dialect_for(resolve_repo!(repo_or_name)).quote_identifier(identifier)

  @doc false
  def apply_filters(_repo_or_adapter, sql, params, []), do: {sql, params}

  def apply_filters(%Adapter{} = adapter, sql, params, filters) do
    Adapter.apply_filters(adapter, sql, params, filters)
  end

  def apply_filters(repo_or_name, sql, params, filters) do
    dialect_for(resolve_repo!(repo_or_name)).apply_filters(sql, params, filters)
  end

  @doc false
  def apply_sorts(_repo_or_adapter, sql, []), do: sql

  def apply_sorts(%Adapter{} = adapter, sql, sorts) do
    Adapter.apply_sorts(adapter, sql, sorts)
  end

  def apply_sorts(repo_or_name, sql, sorts) do
    dialect_for(resolve_repo!(repo_or_name)).apply_sorts(sql, sorts)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolver, do: Config.source_resolver()

  @dialect_impls %{
    Ecto.Adapters.Postgres => Lotus.Source.Adapters.Ecto.Dialects.Postgres,
    Ecto.Adapters.SQLite3 => Lotus.Source.Adapters.Ecto.Dialects.SQLite3,
    Ecto.Adapters.MyXQL => Lotus.Source.Adapters.Ecto.Dialects.MySQL
  }

  defp dialect_for(repo) do
    source_mod = repo.__adapter__()
    Map.get(@dialect_impls, source_mod, Lotus.Source.Adapters.Ecto.Dialects.Default)
  end

  defp dialect_for_error(%{__exception__: true, __struct__: exc_mod}) do
    alias Lotus.Source.Adapters.Ecto.Dialects.Default, as: DefaultDialect

    Enum.find_value(
      Map.values(@dialect_impls) ++ [DefaultDialect],
      DefaultDialect,
      fn impl ->
        if exc_mod in impl.handled_errors(), do: impl, else: false
      end
    )
  end

  defp dialect_for_error(_), do: Lotus.Source.Adapters.Ecto.Dialects.Default

  defp resolve_repo!(source) when is_atom(source) and not is_nil(source), do: source

  defp resolve_repo!(source_name) when is_binary(source_name) do
    Config.get_data_source!(source_name)
  end

  defp resolve_repo!(nil) do
    {_name, mod} = Config.default_data_source()
    mod
  end
end
