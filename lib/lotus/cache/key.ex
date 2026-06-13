defmodule Lotus.Cache.Key do
  @moduledoc false

  @spec result(term(), map() | list(), keyword(), term() | nil) :: binary()
  def result(body, bound, opts, scope \\ nil) do
    Lotus.Config.cache_key_builder().result_key(body, bound, opts, scope)
  end
end
