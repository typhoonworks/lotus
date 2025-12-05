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

  alias Lotus.Config

  @compile {:no_warn_undefined, Cachex}

  @cache_name :lotus_cache
  @tag_cache_name :lotus_cache_tags

  @impl Lotus.Cache.Adapter
  def spec_config do
    Code.ensure_loaded?(Cachex) or
      raise """
      Cachex is not available. Please add {:cachex, "~> 4.0"} to your dependencies.
      """

    cachex_opts =
      case Config.cache_config() do
        %{cachex_opts: opts} when is_list(opts) -> opts
        _ -> [router: {Cachex.Router.Ring, [monitor: true]}]
      end

    [
      Supervisor.child_spec({Cachex, [name: @cache_name] ++ [cachex_opts]},
        id: {Cachex, @cache_name}
      ),
      Supervisor.child_spec({Cachex, [name: @tag_cache_name] ++ [cachex_opts]},
        id: {Cachex, @tag_cache_name}
      )
    ]
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
    compress = Keyword.get(opts, :compress, true)
    encoded = encode(value, compress)
    max_bytes = Keyword.get(opts, :max_bytes, 5_000_000)

    if byte_size(encoded) <= max_bytes do
      case Cachex.put(@cache_name, key, encoded, expire: ttl_ms) do
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

  @impl Lotus.Cache.Adapter
  def delete(key) do
    Cachex.del(@cache_name, key)

    :ok
  end

  @impl Lotus.Cache.Adapter
  def get_or_store(key, ttl_ms, fun, opts) do
    case get(key) do
      {:ok, value} ->
        {:ok, value, :hit}

      :miss ->
        value = fun.()
        put(key, value, ttl_ms, opts)

        {:ok, value, :miss}
    end
  end

  @impl Lotus.Cache.Adapter
  def invalidate_tags(tags) do
    Cachex.transaction(@tag_cache_name, tags, fn tag_cache ->
      for tag <- tags do
        tag_cache
        |> Cachex.get(tag)
        |> delete_tagged_keys()
      end
    end)

    :ok
  end

  defp delete_tagged_keys({:ok, keys}) when is_list(keys) do
    Cachex.transaction(@cache_name, keys, fn key_cache ->
      for key <- keys do
        Cachex.del(key_cache, key)
      end
    end)
  end

  defp delete_tagged_keys(_), do: :noop

  @impl Lotus.Cache.Adapter
  def touch(key, ttl_ms) do
    Cachex.expire(@cache_name, key, ttl_ms)

    :ok
  end

  defp store_tags(tags, key) when is_list(tags) do
    Cachex.transaction(@tag_cache_name, tags, fn cache ->
      for tag <- tags do
        Cachex.get_and_update(cache, tag, fn
          nil -> {:commit, [key]}
          existing_keys -> {:commit, [key | existing_keys]}
        end)
      end
    end)
  end

  defp store_tags(nil, _key), do: :ok
end
