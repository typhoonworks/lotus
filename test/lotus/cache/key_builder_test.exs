defmodule Lotus.Cache.KeyBuilderTest do
  use ExUnit.Case, async: true

  alias Lotus.Cache.KeyBuilder
  alias Lotus.Cache.KeyBuilder.Default

  describe "scope_digest/1" do
    test "returns empty string for nil" do
      assert KeyBuilder.scope_digest(nil) == ""
    end

    test "returns 16-character hex digest for non-nil scope" do
      digest = KeyBuilder.scope_digest(%{tenant_id: 42})
      assert is_binary(digest)
      assert byte_size(digest) == 16
      assert Regex.match?(~r/^[0-9a-f]{16}$/, digest)
    end

    test "produces consistent digests for the same scope" do
      scope = %{role: :admin}
      assert KeyBuilder.scope_digest(scope) == KeyBuilder.scope_digest(scope)
    end

    test "produces different digests for different scopes" do
      digest_a = KeyBuilder.scope_digest(%{tenant_id: 1})
      digest_b = KeyBuilder.scope_digest(%{tenant_id: 2})
      refute digest_a == digest_b
    end
  end

  describe "Default.discovery_key/2" do
    test "builds key without scope suffix for nil scope" do
      key =
        Default.discovery_key(
          %{kind: :list_schemas, source_name: "pg", components: {}, version: "1.0.0"},
          nil
        )

      assert String.starts_with?(key, "schema:list_schemas:pg:")
      refute String.contains?(key, "::" <> "")
    end

    test "builds key with scope suffix for non-nil scope" do
      scope = %{tenant_id: 42}

      key =
        Default.discovery_key(
          %{
            kind: :list_tables,
            source_name: "pg",
            components: {"public", false},
            version: "1.0.0"
          },
          scope
        )

      assert String.starts_with?(key, "schema:list_tables:pg:")
      assert String.ends_with?(key, ":#{KeyBuilder.scope_digest(scope)}")
    end

    test "different components produce different keys" do
      params_a = %{
        kind: :list_tables,
        source_name: "pg",
        components: {"public", false},
        version: "1.0.0"
      }

      params_b = %{
        kind: :list_tables,
        source_name: "pg",
        components: {"reporting", false},
        version: "1.0.0"
      }

      key_a = Default.discovery_key(params_a, nil)
      key_b = Default.discovery_key(params_b, nil)

      refute key_a == key_b
    end

    test "different kinds produce different keys" do
      params_a = %{
        kind: :list_tables,
        source_name: "pg",
        components: {"public", false},
        version: "1.0.0"
      }

      params_b = %{
        kind: :list_relations,
        source_name: "pg",
        components: {"public", false},
        version: "1.0.0"
      }

      key_a = Default.discovery_key(params_a, nil)
      key_b = Default.discovery_key(params_b, nil)

      refute key_a == key_b
    end
  end

  describe "Default.result_key/4" do
    test "builds result key from SQL, params, opts, and nil scope" do
      key =
        Default.result_key(
          "SELECT * FROM users",
          %{id: 1},
          [data_source: "primary", search_path: "public", lotus_version: "1.0.0"],
          nil
        )

      assert String.starts_with?(key, "result:primary:")
    end

    test "different SQL produces different keys" do
      opts = [data_source: "primary", search_path: "", lotus_version: "1.0.0"]
      key_a = Default.result_key("SELECT 1", %{}, opts, nil)
      key_b = Default.result_key("SELECT 2", %{}, opts, nil)

      refute key_a == key_b
    end

    test "handles list params" do
      key =
        Default.result_key(
          "SELECT * FROM users WHERE id = $1",
          [42],
          [data_source: "primary", lotus_version: "1.0.0"],
          nil
        )

      assert String.starts_with?(key, "result:primary:")
    end

    test "nil scope produces same key format as unscoped" do
      opts = [data_source: "primary", search_path: "public", lotus_version: "1.0.0"]
      key = Default.result_key("SELECT 1", %{}, opts, nil)

      assert Regex.match?(~r/^result:primary:[a-f0-9]{64}$/, key)
    end

    test "non-nil scope appends scope digest to key" do
      opts = [data_source: "primary", search_path: "public", lotus_version: "1.0.0"]
      scope = %{tenant_id: 42}
      key = Default.result_key("SELECT 1", %{}, opts, scope)

      expected_suffix = KeyBuilder.scope_digest(scope)
      assert String.ends_with?(key, ":#{expected_suffix}")
      assert Regex.match?(~r/^result:primary:[a-f0-9]{64}:[a-f0-9]{16}$/, key)
    end

    test "different scopes produce different keys for same query" do
      opts = [data_source: "primary", search_path: "public", lotus_version: "1.0.0"]
      sql = "SELECT * FROM users"

      key_a = Default.result_key(sql, %{}, opts, %{tenant_id: 1})
      key_b = Default.result_key(sql, %{}, opts, %{tenant_id: 2})

      refute key_a == key_b
    end

    test "same scope produces same key for same query" do
      opts = [data_source: "primary", search_path: "public", lotus_version: "1.0.0"]
      sql = "SELECT * FROM users"
      scope = %{tenant_id: 42}

      key_a = Default.result_key(sql, %{}, opts, scope)
      key_b = Default.result_key(sql, %{}, opts, scope)

      assert key_a == key_b
    end
  end
end
