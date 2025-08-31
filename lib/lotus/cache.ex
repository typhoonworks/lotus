defmodule Lotus.Cache do
  @moduledoc """
  Lotus cache facade. If no adapter configured, acts as a no-op pass-through.
  """

  alias Lotus.Config

  def enabled?(), do: match?({:ok, _}, adapter())

  def get(key) do
    with {:ok, adapter} <- adapter() do
      adapter.get(ns(key))
    else
      _ -> :miss
    end
  end

  def get_or_store(key, ttl_ms, fun, opts \\ []) do
    with {:ok, adapter} <- adapter() do
      adapter.get_or_store(ns(key), ttl_ms, fun, opts)
    else
      _ ->
        {:ok, fun.(), :miss}
    end
  end

  def put(key, value, ttl_ms, opts \\ []) do
    with {:ok, adapter} <- adapter() do
      adapter.put(ns(key), value, ttl_ms, opts)
    else
      _ -> :ok
    end
  end

  def delete(key) do
    with {:ok, adapter} <- adapter() do
      adapter.delete(ns(key))
    else
      _ -> :ok
    end
  end

  def invalidate_tags(tags) when is_list(tags) do
    with {:ok, adapter} <- adapter(),
         true <- function_exported?(adapter, :invalidate_tags, 1) do
      adapter.invalidate_tags(tags)
    else
      _ -> :ok
    end
  end

  defp ns(key), do: "#{namespace()}:#{key}"

  defp namespace, do: Config.cache_namespace()

  defp adapter, do: Config.cache_adapter()
end
