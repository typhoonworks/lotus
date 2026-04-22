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
              "Data source #{inspect(label)} not configured. " <>
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
  Return the editor configuration for a source.
  """
  @spec editor_config(Adapter.t() | String.t()) :: map()
  def editor_config(%Adapter{} = adapter), do: Adapter.editor_config(adapter)

  def editor_config(source_name) when is_binary(source_name) do
    source_name |> get_source!() |> Adapter.editor_config()
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
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolver, do: Config.source_resolver()
end
