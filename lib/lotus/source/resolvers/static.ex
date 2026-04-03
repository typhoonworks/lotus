defmodule Lotus.Source.Resolvers.Static do
  @moduledoc """
  Default source resolver that reads from static `data_repos` configuration.

  Preserves the resolution priority logic from `Lotus.Sources.resolve!/2`:

    1. `repo_opt` as string name — lookup in data_repos, wrap in adapter
    2. `repo_opt` as module — reverse lookup (find name for module), wrap in adapter
    3. `fallback` as string name — lookup
    4. `fallback` as module — reverse lookup
    5. Both nil — use `Config.default_data_repo()`
    6. Not found — `{:error, :not_found}`
  """

  @behaviour Lotus.Source.Resolver

  alias Lotus.Config
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def resolve(repo_opt, fallback) do
    cond do
      is_binary(repo_opt) ->
        lookup_by_name(repo_opt)

      repo_module?(repo_opt) ->
        lookup_by_module(repo_opt)

      is_binary(fallback) ->
        lookup_by_name(fallback)

      repo_module?(fallback) ->
        lookup_by_module(fallback)

      true ->
        {:ok, default_adapter()}
    end
  end

  @impl true
  def list_sources do
    Config.data_repos()
    |> Enum.map(fn {name, mod} -> EctoAdapter.wrap(name, mod) end)
  end

  @impl true
  def get_source!(name) do
    mod = Config.get_data_repo!(name)
    EctoAdapter.wrap(name, mod)
  end

  @impl true
  def list_source_names do
    Config.list_data_repo_names()
  end

  @impl true
  def default_source do
    {name, mod} = Config.default_data_repo()
    {name, EctoAdapter.wrap(name, mod)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp lookup_by_name(name) do
    case Map.get(Config.data_repos(), name) do
      nil -> {:error, :not_found}
      mod -> {:ok, EctoAdapter.wrap(name, mod)}
    end
  end

  defp lookup_by_module(mod) do
    case Enum.find(Config.data_repos(), fn {_name, m} -> m == mod end) do
      {name, _} -> {:ok, EctoAdapter.wrap(name, mod)}
      nil -> {:error, :not_found}
    end
  end

  defp repo_module?(mod) when is_atom(mod) and not is_nil(mod),
    do: function_exported?(mod, :__adapter__, 0)

  defp repo_module?(_), do: false

  defp default_adapter do
    {name, mod} = Config.default_data_repo()
    EctoAdapter.wrap(name, mod)
  end
end
