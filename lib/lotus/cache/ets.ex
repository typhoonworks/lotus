defmodule Lotus.Cache.ETS do
  @moduledoc """
  An ETS-based, local, in-memory cache adapter for Lotus.

  This is the default cache adapter if none is specified.

  If you want a distributed cache, consider using `Lotus.Cache.Cachex`.
  """

  use Lotus.Cache.Adapter

  @table :lotus_cache
  @tag_table :lotus_cache_tags

  def child_spec(_opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :supervisor
    }
  end

  def start_link(_opts) do
    ensure_tables!()
    start_janitor()
    {:ok, self()}
  end

  @impl Lotus.Cache.Adapter
  def spec_config do
    [{Lotus.Cache.ETS, []}]
  end

  @impl Lotus.Cache.Adapter
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value_bin, expires_at}] ->
        if expired?(expires_at) do
          :ets.delete(@table, key)
          :miss
        else
          {:ok, decode(value_bin)}
        end

      _ ->
        :miss
    end
  end

  @impl Lotus.Cache.Adapter
  def put(key, value, ttl_ms, opts) do
    encoded = encode(value)

    max_bytes = Keyword.get(opts, :max_bytes, 5_000_000)
    if byte_size(encoded) > max_bytes, do: :ok, else: do_put(key, encoded, ttl_ms, opts)
  end

  defp do_put(key, bin, ttl_ms, opts) do
    expires_at = now_ms() + ttl_ms
    :ets.insert(@table, {key, bin, expires_at})
    for t <- Keyword.get(opts, :tags, []), do: :ets.insert(@tag_table, {t, key})
    :ok
  end

  @impl Lotus.Cache.Adapter
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  @impl Lotus.Cache.Adapter
  def touch(key, ttl_ms) do
    case :ets.lookup(@table, key) do
      [{^key, v, _old}] ->
        :ets.insert(@table, {key, v, now_ms() + ttl_ms})
        :ok

      _ ->
        :ok
    end
  end

  @impl Lotus.Cache.Adapter
  def get_or_store(key, ttl_ms, fun, opts) do
    case get(key) do
      {:ok, v} ->
        {:ok, v, :hit}

      :miss ->
        lock = {:lotus_cache_lock, key}

        case :global.set_lock(lock, [node()], Keyword.get(opts, :lock_timeout, 10_000)) do
          true ->
            try do
              case get(key) do
                {:ok, v} ->
                  {:ok, v, :hit}

                :miss ->
                  value = fun.()
                  put(key, value, ttl_ms, opts)
                  {:ok, value, :miss}
              end
            after
              :global.del_lock(lock)
            end

          false ->
            value = fun.()
            {:ok, value, :miss}
        end
    end
  end

  @impl Lotus.Cache.Adapter
  def invalidate_tags(tags) do
    for tag <- tags do
      for {^tag, key} <- :ets.lookup(@tag_table, tag) do
        :ets.delete(@table, key)
        :ets.delete_object(@tag_table, {tag, key})
      end
    end

    :ok
  end

  defp ensure_tables! do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    unless :ets.whereis(@tag_table) != :undefined do
      :ets.new(@tag_table, [:bag, :named_table, :public, write_concurrency: true])
    end
  end

  defp start_janitor do
    spawn_link(fn -> janitor_loop() end)
  end

  defp janitor_loop do
    Process.sleep(:timer.seconds(30))
    now = now_ms()

    for {key, _v, expires_at} <- :ets.tab2list(@table), expires_at <= now do
      :ets.delete(@table, key)
    end

    janitor_loop()
  end

  defp expired?(ts), do: ts <= now_ms()
  defp now_ms, do: System.monotonic_time(:millisecond)
end
