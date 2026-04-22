defmodule Lotus.Source.Resolvers.Static do
  @moduledoc """
  Default source resolver that reads from static `data_sources` configuration.

  Preserves the resolution priority logic from `Lotus.Sources.resolve!/2`:

    1. `source_opt` as string name — lookup in data_sources, wrap in adapter
    2. `source_opt` as module — reverse lookup (find name for module), wrap in adapter
    3. `fallback` as string name — lookup
    4. `fallback` as module — reverse lookup
    5. Both nil — use `Config.default_data_source()`
    6. Not found — `{:error, :not_found}`
  """

  @behaviour Lotus.Source.Resolver

  alias Lotus.Config
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def resolve(source_opt, fallback) do
    cond do
      is_binary(source_opt) ->
        lookup_by_name(source_opt)

      source_module?(source_opt) ->
        lookup_by_module(source_opt)

      is_binary(fallback) ->
        lookup_by_name(fallback)

      source_module?(fallback) ->
        lookup_by_module(fallback)

      true ->
        {:ok, default_adapter()}
    end
  end

  @impl true
  def list_sources do
    Config.data_sources()
    |> Enum.map(fn {name, mod} -> wrap_entry(name, mod) end)
  end

  @impl true
  def get_source!(name) do
    mod = Config.get_data_source!(name)
    wrap_entry(name, mod)
  end

  @impl true
  def list_source_names do
    Config.list_data_source_names()
  end

  @impl true
  def default_source do
    {name, mod} = Config.default_data_source()
    {name, wrap_entry(name, mod)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp lookup_by_name(name) do
    case Map.get(Config.data_sources(), name) do
      nil -> {:error, :not_found}
      mod -> {:ok, wrap_entry(name, mod)}
    end
  end

  defp lookup_by_module(mod) do
    case Enum.find(Config.data_sources(), fn {_name, m} -> m == mod end) do
      {name, _} -> {:ok, wrap_entry(name, mod)}
      nil -> {:error, :not_found}
    end
  end

  defp wrap_entry(name, entry) do
    case find_adapter(entry) do
      {:ok, adapter_mod} ->
        adapter_mod.wrap(name, entry)

      :none when is_atom(entry) ->
        # Atom entries fall back to EctoAdapter — it handles unknown Ecto
        # dialects by wrapping them with a default source_type.
        EctoAdapter.wrap(name, entry)

      :none ->
        raise ArgumentError, """
        No source adapter can handle data source #{inspect(name)}.

        The configured entry was:

            #{inspect(entry)}

        For non-Ecto sources (maps, tuples, etc.), configure a matching
        adapter in `:lotus, :source_adapters` and ensure its `can_handle?/1`
        returns true for this entry.
        """
    end
  end

  defp find_adapter(entry) do
    all_adapters = Config.source_adapters() ++ EctoAdapter.builtin_adapters()

    case Enum.find(all_adapters, & &1.can_handle?(entry)) do
      nil -> :none
      mod -> {:ok, mod}
    end
  end

  # Accepts any loaded module (Ecto repo or non-Ecto adapter module). Rejects
  # bare atoms (e.g. :typoed_name) so they fall through the resolver's cond
  # chain instead of committing to a failing module lookup.
  defp source_module?(mod) when is_atom(mod) and not is_nil(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :module_info, 0)
  end

  defp source_module?(_), do: false

  defp default_adapter do
    {name, mod} = Config.default_data_source()
    wrap_entry(name, mod)
  end
end
