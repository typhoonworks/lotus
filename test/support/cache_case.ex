defmodule Lotus.CacheCase do
  @moduledoc """
  This module defines the setup for cache-related tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Lotus.CacheCase
    end
  end

  setup do
    cleanup_cache_tables()

    {:ok, _} = Lotus.Cache.ETS.start_link([])

    on_exit(fn -> cleanup_cache_tables() end)

    :ok
  end

  defp cleanup_cache_tables do
    try do
      if :ets.whereis(:lotus_cache) != :undefined do
        :ets.delete(:lotus_cache)
      end
    rescue
      ArgumentError -> :ok
    end

    try do
      if :ets.whereis(:lotus_cache_tags) != :undefined do
        :ets.delete(:lotus_cache_tags)
      end
    rescue
      ArgumentError -> :ok
    end
  end
end
