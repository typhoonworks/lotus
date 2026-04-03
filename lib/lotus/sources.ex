defmodule Lotus.Sources do
  @moduledoc false

  alias Lotus.Config
  alias Lotus.Source.Adapter

  @doc """
  Resolve to an `%Adapter{}` struct.

  Accepts:
    * `repo_opt` — configured name (string) or repo module (atom) or nil
    * `q_repo`   — query's stored repo (string or module) or nil

  Falls back to the default source. Raises on resolution failure.
  """
  @spec resolve!(nil | String.t() | module(), nil | String.t() | module()) :: Adapter.t()
  def resolve!(repo_opt, q_repo) do
    case resolver().resolve(repo_opt, q_repo) do
      {:ok, %Adapter{} = adapter} ->
        adapter

      {:error, :not_found} ->
        available = resolver().list_source_names()
        label = repo_opt || q_repo

        raise ArgumentError,
              "Data repo '#{label}' not configured. " <>
                "Available repos: #{inspect(available)}"
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
    case Enum.find(Config.data_repos(), fn {_name, m} -> m == mod end) do
      {name, _} ->
        name

      nil ->
        raise ArgumentError,
              "Repo module #{inspect(mod)} isn't in :lotus, :data_repos. " <>
                "Configured names: #{inspect(Map.keys(Config.data_repos()))}"
    end
  end

  @doc """
  Detect the source type from an adapter, repository module, or name.
  """
  @spec source_type(Adapter.t() | module() | String.t()) ::
          :postgres | :mysql | :sqlite | :other
  def source_type(%Adapter{source_type: st}), do: st

  def source_type(repo_name) when is_binary(repo_name) do
    repo = Config.get_data_repo!(repo_name)
    source_type(repo)
  end

  def source_type(repo) when is_atom(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      Ecto.Adapters.MyXQL -> :mysql
      _ -> :other
    end
  end

  @doc """
  Whether a source type supports a specific feature.
  """
  @spec supports_feature?(atom(), atom()) :: boolean()
  def supports_feature?(:postgres, :search_path), do: true
  def supports_feature?(:postgres, :make_interval), do: true
  def supports_feature?(:postgres, :arrays), do: true
  def supports_feature?(:postgres, :json), do: true

  def supports_feature?(:mysql, :search_path), do: false
  def supports_feature?(:mysql, :make_interval), do: false
  def supports_feature?(:mysql, :arrays), do: false
  def supports_feature?(:mysql, :json), do: true

  def supports_feature?(:sqlite, :search_path), do: false
  def supports_feature?(:sqlite, :make_interval), do: false
  def supports_feature?(:sqlite, :arrays), do: false
  def supports_feature?(:sqlite, :json), do: true

  def supports_feature?(_, _), do: false

  defp resolver, do: Config.source_resolver()
end
