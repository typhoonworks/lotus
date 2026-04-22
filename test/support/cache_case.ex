defmodule Lotus.CacheCase do
  @moduledoc """
  This module defines the setup for cache-related tests.

  The `Lotus.Cache.ETS` GenServer is started globally by `Lotus.Application`,
  so its tables already exist for the duration of the test run. Each test just
  needs a clean slate, so the setup clears table contents rather than tearing
  down and re-creating the tables (which would strand the running GenServer).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Lotus.CacheCase
    end
  end

  setup do
    clear_cache_tables()
    on_exit(&clear_cache_tables/0)
    :ok
  end

  defp clear_cache_tables do
    for table <- [:lotus_cache, :lotus_cache_tags] do
      if :ets.whereis(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end

    :ok
  end
end
