defmodule Lotus.Cache.ScopeInvalidationTest do
  use Lotus.CacheCase
  use Mimic

  alias Lotus.Cache
  alias Lotus.Cache.KeyBuilder
  alias Lotus.Config

  setup :verify_on_exit!

  setup do
    Mimic.copy(Lotus.Config)

    Config
    |> stub(:cache_adapter, fn -> {:ok, Lotus.Cache.ETS} end)
    |> stub(:cache_namespace, fn -> "test_scope" end)

    :ok
  end

  describe "invalidate_scope/1" do
    test "clears entries tagged with the given scope" do
      scope_a = %{tenant_id: 1}
      tag = "scope:#{KeyBuilder.scope_digest(scope_a)}"

      Cache.put("key_a", "value_a", 5000, tags: [tag])

      assert Cache.get("key_a") == {:ok, "value_a"}

      assert :ok = Cache.invalidate_scope(scope_a)

      assert Cache.get("key_a") == :miss
    end

    test "does not affect entries for a different scope" do
      scope_a = %{tenant_id: 1}
      scope_b = %{tenant_id: 2}
      tag_a = "scope:#{KeyBuilder.scope_digest(scope_a)}"
      tag_b = "scope:#{KeyBuilder.scope_digest(scope_b)}"

      Cache.put("key_a", "value_a", 5000, tags: [tag_a])
      Cache.put("key_b", "value_b", 5000, tags: [tag_b])

      assert :ok = Cache.invalidate_scope(scope_a)

      assert Cache.get("key_a") == :miss
      assert Cache.get("key_b") == {:ok, "value_b"}
    end

    test "does not affect nil-scope entries" do
      scope_a = %{tenant_id: 1}
      tag_a = "scope:#{KeyBuilder.scope_digest(scope_a)}"

      Cache.put("scoped_key", "scoped_value", 5000, tags: [tag_a])
      Cache.put("unscoped_key", "unscoped_value", 5000, tags: ["repo:test"])

      assert :ok = Cache.invalidate_scope(scope_a)

      assert Cache.get("scoped_key") == :miss
      assert Cache.get("unscoped_key") == {:ok, "unscoped_value"}
    end

    test "handles multiple entries for the same scope" do
      scope = %{role: :admin}
      tag = "scope:#{KeyBuilder.scope_digest(scope)}"

      Cache.put("admin_key_1", "v1", 5000, tags: [tag, "schema:list_schemas"])
      Cache.put("admin_key_2", "v2", 5000, tags: [tag, "schema:list_tables"])
      Cache.put("admin_key_3", "v3", 5000, tags: [tag, "schema:list_relations"])

      assert :ok = Cache.invalidate_scope(scope)

      assert Cache.get("admin_key_1") == :miss
      assert Cache.get("admin_key_2") == :miss
      assert Cache.get("admin_key_3") == :miss
    end

    test "returns :ok when cache is disabled" do
      Config
      |> stub(:cache_adapter, fn -> :error end)

      assert :ok = Cache.invalidate_scope(%{tenant_id: 1})
    end
  end
end
