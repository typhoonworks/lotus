defmodule Lotus.ConfigTest do
  use ExUnit.Case, async: false

  alias Lotus.Config

  @preserved_keys [:cache, :table_visibility, :schema_visibility, :column_visibility]

  setup do
    originals = Map.new(@preserved_keys, &{&1, Application.get_env(:lotus, &1)})

    on_exit(fn ->
      for {key, value} <- originals do
        if is_nil(value) do
          Application.delete_env(:lotus, key)
        else
          Application.put_env(:lotus, key, value)
        end
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

  describe "visibility rules lookups" do
    @variants [
      {:rules_for_repo_name, :table_visibility},
      {:schema_rules_for_repo_name, :schema_visibility},
      {:column_rules_for_repo_name, :column_visibility}
    ]

    test "returns repo-specific rules when repo_name matches a configured key" do
      rules = [deny: ["secret_table"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: rules})

        assert apply(Config, fun, ["postgres"]) == rules,
               "#{fun} did not return repo-specific rules"
      end
    end

    test "returns an empty list when the repo-specific value is an empty list" do
      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: [], default: [deny: ["should_not_see"]]})

        assert apply(Config, fun, ["postgres"]) == [],
               "#{fun} did not return empty list for empty repo-specific value"
      end
    end

    test "falls through to :default when the repo-specific value is nil" do
      default_rules = [deny: ["default_rule"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: nil, default: default_rules})

        assert apply(Config, fun, ["postgres"]) == default_rules,
               "#{fun} did not fall through to :default for nil repo-specific value"
      end
    end

    test "returns :default rules when repo_name has no match and :default is present" do
      default_rules = [deny: ["default_rule"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{other_repo: [deny: ["other"]], default: default_rules})

        assert apply(Config, fun, ["postgres"]) == default_rules,
               "#{fun} did not fall through to :default"
      end
    end

    test "returns an empty list when repo_name has no match and :default is absent" do
      for {fun, key} <- @variants do
        put_visibility(key, %{other_repo: [deny: ["other"]]})

        assert apply(Config, fun, ["postgres"]) == [],
               "#{fun} did not return [] when no match and no :default"
      end
    end

    test "returns an empty list when the visibility map is missing entirely" do
      for {fun, key} <- @variants do
        Application.delete_env(:lotus, key)
        Config.reload!()

        assert apply(Config, fun, ["postgres"]) == [],
               "#{fun} did not return [] when visibility map is missing"
      end
    end

    test "returns :default rules for an arbitrary repo_name string with no matching key" do
      unknown = "lotus_config_test_unknown_#{System.unique_integer([:positive])}"
      default_rules = [deny: ["secret"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: [deny: ["should_not_match"]], default: default_rules})

        assert apply(Config, fun, [unknown]) == default_rules,
               "#{fun} did not return :default rules for unknown repo_name"
      end
    end
  end

  defp put_visibility(key, value) do
    Application.put_env(:lotus, key, value)
    Config.reload!()
  end
end
