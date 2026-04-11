defmodule Lotus.Cache.Key do
  @moduledoc false

  @spec result(binary(), map() | list(), keyword()) :: binary()
  def result(sql, bound, opts) do
    Lotus.Config.cache_key_builder().result_key(sql, bound, opts)
  end
end
