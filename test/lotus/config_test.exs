defmodule Lotus.ConfigTest do
  use ExUnit.Case, async: false

  alias Lotus.Config

  setup do
    original = Application.get_env(:lotus, :cache)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:lotus, :cache)
      else
        Application.put_env(:lotus, :cache, original)
      end

      Config.reload!()
    end)

    :ok
  end

  describe "cache_namespace/0" do
    test "returns the default namespace when no cache is configured" do
      Application.delete_env(:lotus, :cache)
      Config.reload!()

      assert Config.cache_namespace() == "lotus:v1"
    end

    test "returns the default namespace when cache is configured without an explicit namespace" do
      Application.put_env(:lotus, :cache, %{adapter: Lotus.Cache.ETS})
      Config.reload!()

      assert Config.cache_namespace() == "lotus:v1"
    end

    test "returns the configured namespace when explicitly set" do
      Application.put_env(:lotus, :cache, %{
        adapter: Lotus.Cache.ETS,
        namespace: "my_app:v3"
      })

      Config.reload!()

      assert Config.cache_namespace() == "my_app:v3"
    end
  end
end
