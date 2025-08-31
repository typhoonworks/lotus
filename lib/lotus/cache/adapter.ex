defmodule Lotus.Cache.Adapter do
  @moduledoc """
  Cache adapter behaviour. Implement this to support Redis/Cachex/Mnesia, etc.
  """

  @type key :: binary()
  @type value :: any()
  @type ttl_ms :: non_neg_integer()
  @type opts :: Keyword.t()

  @callback get(key) :: {:ok, value} | :miss | {:error, term}
  @callback put(key, value, ttl_ms, opts) :: :ok | {:error, term}
  @callback delete(key) :: :ok | {:error, term}
  @callback get_or_store(key, ttl_ms, (-> value), opts) ::
              {:ok, value, :hit | :miss} | {:error, term}

  @callback invalidate_tags([binary()]) :: :ok | {:error, term}
  @callback touch(key, ttl_ms) :: :ok | {:error, term}
end
