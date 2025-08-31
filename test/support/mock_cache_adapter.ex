defmodule Lotus.Test.MockCacheAdapter do
  @moduledoc """
  Mock cache adapter for testing that doesn't support invalidate_tags.
  """

  @behaviour Lotus.Cache.Adapter

  def get(_key), do: :miss
  def put(_key, _value, _ttl, _opts), do: :ok
  def delete(_key), do: :ok
  def get_or_store(_key, _ttl, fun, _opts), do: {:ok, fun.(), :miss}
  def touch(_key, _ttl), do: :ok
  def invalidate_tags(_tags), do: :ok
end
