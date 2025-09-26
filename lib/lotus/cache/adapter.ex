defmodule Lotus.Cache.Adapter do
  @moduledoc """
  Behaviour specification for cache adapters in the Lotus framework.

  All cache adapters must implement this behavior.

  Cache adapters are only meant to be used internally by Lotus and should not be
  called directly by application code, as their implementation may change without notice.

  ## Built-in Adapters

  - `Lotus.Cache.ETS` - Default ETS-based local in-memory cache
  - `Lotus.Cache.Cachex` - Cachex-based cache supporting local and distributed modes

  ## Configuration

  Configure your chosen adapter in your application config:

      config :lotus,
        cache: %{
          adapter: MyApp.CustomCacheAdapter,
          # adapter-specific options...
        }

  """

  @typedoc false
  @type key :: binary()

  @typedoc false
  @type value :: any()

  @typedoc "How long the cache entry should live, in milliseconds"
  @type ttl_ms :: non_neg_integer()

  @typedoc "Options passed to cache operations"
  @type opts :: Keyword.t()

  @doc """
  Returns the adapter specification configuration.

  This should return a keyword list of configuration options specific to the adapter.

  Called by `Lotus.Supervisor` to start the cache adapter under the supervisor.
  """
  @callback spec_config :: keyword()

  @doc """
  Retrieves a value from the cache by key.
  """
  @callback get(key) :: {:ok, value} | :miss | {:error, term}

  @doc """
  Stores a value in the cache with the given key and TTL.
  """
  @callback put(key, value, ttl_ms, opts) :: :ok | {:error, term}

  @doc """
  Removes a value from the cache by key.
  """
  @callback delete(key) :: :ok | {:error, term}

  @doc """
  Retrieves a value from cache or stores it if missing.
  """
  @callback get_or_store(key, ttl_ms, (-> value), opts) ::
              {:ok, value, :hit | :miss} | {:error, term}

  @doc """
  Invalidates all cache entries associated with the given tags.

  Tags allow for bulk invalidation of related cache entries. When a tag is
  invalidated, all cache entries that were stored with that tag are removed.

  ## Parameters

  - `tags` - List of tag names to invalidate
  """
  @callback invalidate_tags([binary()]) :: :ok | {:error, term}

  @doc """
  Updates the TTL of an existing cache entry without modifying its value.
  """
  @callback touch(key, ttl_ms) :: :ok | {:error, term}
end
