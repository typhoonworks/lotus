defmodule Lotus.Cache.Cachex do
  @moduledoc """
  A Cachex-based, local or distributed, in-memory cache adapter for Lotus.

  This adapter requires the `Cachex` library. Please add `{:cachex, "~> 4.0"}` to your dependencies.

  Example configuration in `config/config.exs`:

      config :lotus, :cache,
        adapter: Lotus.Cache.Cachex,
        cachex_opts: [limit: 1_000_000] # Optional Cachex options

  See [Cachex documentation](https://hexdocs.pm/cachex/) for available options. By default,
  Cachex will use a local-only routing strategy. To enable distributed caching, you can
  choose your preferred router by [following the instructions in the Cachex docs](https://hexdocs.pm/cachex/cache-routers.html#default-routers).
  """

  use Lotus.Cache.Adapter

  import Cachex.Spec

  alias Lotus.Config

  @cache_name :lotus_cache
  @tag_cache_name :lotus_cache_tags

  def child_spec(_opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :supervisor
    }
  end

  def start_link(_opts) do
    Code.ensure_loaded?(Cachex) or
      raise """
      Cachex is not available. Please add {:cachex, "~> 4.0"} to your dependencies.
      """

    {:ok, self()}
  end

  @impl Lotus.Cache.Adapter
  def spec_config do
    Code.ensure_loaded?(Cachex) or
      raise """
      Cachex is not available. Please add {:cachex, "~> 4.0"} to your dependencies.
      """

    cachex_opts =
      case Config.cache_config() do
        %{cachex_opts: opts} when is_list(opts) -> opts
        _ -> [router: router(module: Cachex.Router.Ring, options: [monitor: true])]
      end

    [{Cachex, [:lotus_cache, cachex_opts]}]
  end

  @impl Lotus.Cache.Adapter
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, decode(value)}
    end
  end

  @impl Lotus.Cache.Adapter
  def put(key, value, ttl_ms, opts) do
    do_put(@cache_name, key, value, ttl_ms, opts)
  end

  @impl Lotus.Cache.Adapter
  def delete(key) do
    Cachex.del(@cache_name, key)

    :ok
  end

  @impl Lotus.Cache.Adapter
  def get_or_store(key, ttl_ms, fun, opts) do
    Cachex.transaction(@cache_name, [key], fn cache ->
      case get(key) do
        {:ok, value} ->
          {:ok, value, :hit}

        :miss ->
          value = fun.()
          do_put(cache, key, value, ttl_ms, opts)
      end
    end)
  end

  @impl Lotus.Cache.Adapter
  def invalidate_tags(tags) do
    Cachex.transaction(@tag_cache_name, tags, fn cache ->
      Enum.each(tags, fn tag ->
        Cachex.del(cache, tag)
      end)
    end)

    :ok
  end

  @impl Lotus.Cache.Adapter
  def touch(key, ttl_ms) do
    Cachex.expire(@cache_name, key, ttl_ms)
  end

  defp do_put(cache, key, value, ttl_ms, opts) do
    encoded = encode(value)
    max_bytes = Keyword.get(opts, :max_bytes, 5_000_000)

    if byte_size(encoded) <= max_bytes do
      case Cachex.put(cache, key, encoded, expire: ttl_ms) do
        {:ok, true} ->
          tags = Keyword.get(opts, :tags)
          store_tags(tags, key)

          :ok

        {:ok, false} ->
          {:error, :put_failed}
      end
    else
      :ok
    end
  end

  defp store_tags([tag], key), do: Cachex.put(@tag_cache_name, tag, key)

  defp store_tags(tags, key) when is_list(tags) do
    key_value_pairs = Enum.map(tags, fn tag -> {tag, key} end)
    Cachex.put_many(@tag_cache_name, key_value_pairs)
  end

  defp store_tags(nil, _key), do: :ok
end
