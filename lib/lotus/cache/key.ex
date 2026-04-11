defmodule Lotus.Cache.Key do
  @moduledoc false

  @spec result(binary(), map() | list(), keyword(), term() | nil) :: binary()
  def result(sql, bound, opts, scope \\ nil) do
    Lotus.Config.cache_key_builder().result_key(sql, bound, opts, scope)
  end
end
