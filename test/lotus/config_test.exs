defmodule Lotus.ConfigTest do
  use ExUnit.Case, async: false

  alias Lotus.Config

  import ExUnit.CaptureLog

  @preserved_keys [
    :cache,
    :table_visibility,
    :schema_visibility,
    :column_visibility,
    :data_sources,
    :data_repos,
    :default_source,
    :default_repo
  ]

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
      {:rules_for_source_name, :table_visibility},
      {:schema_rules_for_source_name, :schema_visibility},
      {:column_rules_for_source_name, :column_visibility}
    ]

    test "returns source-specific rules when source_name matches a configured key" do
      rules = [deny: ["secret_table"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: rules})

        assert apply(Config, fun, ["postgres"]) == rules,
               "#{fun} did not return source-specific rules"
      end
    end

    test "returns an empty list when the source-specific value is an empty list" do
      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: [], default: [deny: ["should_not_see"]]})

        assert apply(Config, fun, ["postgres"]) == [],
               "#{fun} did not return empty list for empty source-specific value"
      end
    end

    test "falls through to :default when the source-specific value is nil" do
      default_rules = [deny: ["default_rule"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: nil, default: default_rules})

        assert apply(Config, fun, ["postgres"]) == default_rules,
               "#{fun} did not fall through to :default for nil source-specific value"
      end
    end

    test "returns :default rules when source_name has no match and :default is present" do
      default_rules = [deny: ["default_rule"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{other_source: [deny: ["other"]], default: default_rules})

        assert apply(Config, fun, ["postgres"]) == default_rules,
               "#{fun} did not fall through to :default"
      end
    end

    test "returns an empty list when source_name has no match and :default is absent" do
      for {fun, key} <- @variants do
        put_visibility(key, %{other_source: [deny: ["other"]]})

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

    test "returns :default rules for an arbitrary source_name string with no matching key" do
      unknown = "lotus_config_test_unknown_#{System.unique_integer([:positive])}"
      default_rules = [deny: ["secret"]]

      for {fun, key} <- @variants do
        put_visibility(key, %{postgres: [deny: ["should_not_match"]], default: default_rules})

        assert apply(Config, fun, [unknown]) == default_rules,
               "#{fun} did not return :default rules for unknown source_name"
      end
    end
  end

  describe "deprecated config key backward compatibility" do
    test "data_repos config key still works and resolves correctly" do
      original_sources = Application.get_env(:lotus, :data_sources)
      Application.delete_env(:lotus, :data_sources)
      Application.put_env(:lotus, :data_repos, %{"test" => Lotus.Test.Repo})

      log =
        capture_log(fn ->
          Config.reload!()
          assert Config.data_sources() == %{"test" => Lotus.Test.Repo}
        end)

      assert log =~ "deprecated"
      assert log =~ ":data_repos"
      assert log =~ ":data_sources"

      Application.delete_env(:lotus, :data_repos)
      Application.put_env(:lotus, :data_sources, original_sources)
      Config.reload!()
    end

    test "default_repo config key still works with warning" do
      original_source = Application.get_env(:lotus, :default_source)
      Application.delete_env(:lotus, :default_source)
      Application.put_env(:lotus, :default_repo, "postgres")

      log =
        capture_log(fn ->
          Config.reload!()
          {name, _mod} = Config.default_data_source()
          assert name == "postgres"
        end)

      assert log =~ "deprecated"
      assert log =~ ":default_repo"
      assert log =~ ":default_source"

      Application.delete_env(:lotus, :default_repo)

      if original_source do
        Application.put_env(:lotus, :default_source, original_source)
      end

      Config.reload!()
    end

    test "both data_repos and data_sources present raises error" do
      Application.put_env(:lotus, :data_repos, %{"old" => Lotus.Test.Repo})

      assert_raise ArgumentError, ~r/Cannot configure both/, fn ->
        Config.reload!()
      end

      Application.delete_env(:lotus, :data_repos)
      Config.reload!()
    end

    test "both default_repo and default_source present raises error" do
      Application.put_env(:lotus, :default_repo, "old")

      assert_raise ArgumentError, ~r/Cannot configure both/, fn ->
        Config.reload!()
      end

      Application.delete_env(:lotus, :default_repo)
      Config.reload!()
    end
  end

  defp put_visibility(key, value) do
    Application.put_env(:lotus, key, value)
    Config.reload!()
  end
end
