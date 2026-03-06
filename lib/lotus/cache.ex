defmodule Lotus.Cache do
  @moduledoc """
  Lotus cache facade. If no adapter configured, acts as a no-op pass-through.
  """

  alias Lotus.{Config, Telemetry}

  def enabled?, do: match?({:ok, _}, adapter())

  def get(key) do
    case adapter() do
      {:ok, adapter} ->
        case adapter.get(ns(key)) do
          {:ok, _} = hit ->
            Telemetry.cache_hit(key)
            hit

          :miss ->
            Telemetry.cache_miss(key)
            :miss
        end

      _ ->
        :miss
    end
  end

  def get_or_store(key, ttl_ms, fun, opts \\ []) do
    case adapter() do
      {:ok, adapter} ->
        case adapter.get_or_store(ns(key), ttl_ms, fun, opts) do
          {:ok, _val, :hit} = result ->
            Telemetry.cache_hit(key)
            result

          {:ok, _val, _miss_or_other} = result ->
            Telemetry.cache_miss(key)
            Telemetry.cache_put(key, ttl_ms)
            result

          other ->
            other
        end

      _ ->
        {:ok, fun.(), :miss}
    end
  end

  def put(key, value, ttl_ms, opts \\ []) do
    case adapter() do
      {:ok, adapter} ->
        result = adapter.put(ns(key), value, ttl_ms, opts)
        Telemetry.cache_put(key, ttl_ms)
        result

      _ ->
        :ok
    end
  end

  def delete(key) do
    case adapter() do
      {:ok, adapter} -> adapter.delete(ns(key))
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
