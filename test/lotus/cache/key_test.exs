defmodule Lotus.Cache.KeyTest do
  use ExUnit.Case

  alias Lotus.Cache.Key

  describe "result/3" do
    test "generates consistent cache keys for same parameters" do
      sql = "SELECT * FROM users WHERE active = $1 AND created_at > $2"
      bound_vars = %{"1" => true, "2" => ~D[2023-01-01]}
      opts = [data_repo: "my_repo", search_path: "public", lotus_version: "1.0.0"]

      key1 = Key.result(sql, bound_vars, opts)
      key2 = Key.result(sql, bound_vars, opts)

      assert key1 == key2
      assert String.starts_with?(key1, "result:my_repo:")
    end

    test "generates different keys for different SQL queries" do
      bound_vars = %{"1" => 123}
      opts = [data_repo: "my_repo"]

      key1 = Key.result("SELECT * FROM users WHERE id = $1", bound_vars, opts)
      key2 = Key.result("SELECT * FROM orders WHERE user_id = $1", bound_vars, opts)

      assert key1 != key2
    end

    test "generates different keys for different bound variables" do
      sql = "SELECT * FROM users WHERE id = $1"
      opts = [data_repo: "my_repo"]

      key1 = Key.result(sql, %{"1" => 123}, opts)
      key2 = Key.result(sql, %{"1" => 456}, opts)

      assert key1 != key2
    end

    test "generates different keys for different data repositories" do
      sql = "SELECT * FROM users WHERE id = $1"
      bound_vars = %{"1" => 123}

      key1 = Key.result(sql, bound_vars, data_repo: "repo1")
      key2 = Key.result(sql, bound_vars, data_repo: "repo2")

      assert key1 != key2
      assert String.starts_with?(key1, "result:repo1:")
      assert String.starts_with?(key2, "result:repo2:")
    end

    test "generates different keys for different search paths" do
      sql = "SELECT * FROM users WHERE id = $1"
      bound_vars = %{"1" => 123}
      base_opts = [data_repo: "my_repo"]

      key1 = Key.result(sql, bound_vars, base_opts ++ [search_path: "public"])
      key2 = Key.result(sql, bound_vars, base_opts ++ [search_path: "tenant1"])

      assert key1 != key2
    end

    test "generates different keys for different lotus versions" do
      sql = "SELECT * FROM users WHERE id = $1"
      bound_vars = %{"1" => 123}
      base_opts = [data_repo: "my_repo"]

      key1 = Key.result(sql, bound_vars, base_opts ++ [lotus_version: "1.0.0"])
      key2 = Key.result(sql, bound_vars, base_opts ++ [lotus_version: "1.1.0"])

      assert key1 != key2
    end

    test "handles complex SQL queries with multiple parameters" do
      sql = """
      SELECT u.id, u.name, u.email, COUNT(o.id) as order_count
      FROM users u
      LEFT JOIN orders o ON u.id = o.user_id
      WHERE u.created_at BETWEEN $1 AND $2
        AND u.status = $3
        AND u.country_code IN ($4, $5, $6)
      GROUP BY u.id, u.name, u.email
      HAVING COUNT(o.id) > $7
      ORDER BY u.created_at DESC
      LIMIT $8 OFFSET $9
      """

      bound_vars = %{
        "1" => ~D[2023-01-01],
        "2" => ~D[2023-12-31],
        "3" => "active",
        "4" => "US",
        "5" => "CA",
        "6" => "UK",
        "7" => 5,
        "8" => 100,
        "9" => 0
      }

      opts = [data_repo: "analytics_repo", search_path: "reports"]

      key = Key.result(sql, bound_vars, opts)

      assert String.starts_with?(key, "result:analytics_repo:")
      assert String.length(key) > 20
    end

    test "handles various data types in bound variables" do
      sql = "SELECT * FROM mixed_data WHERE col1 = $1 AND col2 = $2 AND col3 = $3 AND col4 = $4"

      bound_vars = %{
        "1" => 42,
        "2" => 3.14159,
        "3" => "hello world",
        "4" => ~D[2023-06-15]
      }

      opts = [data_repo: "test_repo"]
      key = Key.result(sql, bound_vars, opts)

      assert String.starts_with?(key, "result:test_repo:")
    end

    test "handles empty bound variables" do
      sql = "SELECT COUNT(*) FROM users"
      bound_vars = %{}
      opts = [data_repo: "my_repo"]

      key = Key.result(sql, bound_vars, opts)

      assert String.starts_with?(key, "result:my_repo:")
    end

    test "handles nil values in bound variables" do
      sql = "SELECT * FROM users WHERE optional_field = $1"
      bound_vars = %{"1" => nil}
      opts = [data_repo: "my_repo"]

      key = Key.result(sql, bound_vars, opts)

      assert String.starts_with?(key, "result:my_repo:")
    end

    test "generates deterministic keys across processes" do
      sql = "SELECT * FROM users WHERE id = $1"
      bound_vars = %{"1" => 123}
      opts = [data_repo: "my_repo"]

      task1 = Task.async(fn -> Key.result(sql, bound_vars, opts) end)
      task2 = Task.async(fn -> Key.result(sql, bound_vars, opts) end)

      key1 = Task.await(task1)
      key2 = Task.await(task2)

      assert key1 == key2
    end

    test "requires data_repo option" do
      sql = "SELECT * FROM users"
      bound_vars = %{}

      assert_raise KeyError, fn ->
        Key.result(sql, bound_vars, [])
      end
    end

    test "handles list params for ad-hoc SQL" do
      sql = "SELECT * FROM users WHERE id = $1 AND status = $2"
      params = [123, "active"]
      opts = [data_repo: "my_repo"]

      key = Key.result(sql, params, opts)

      assert String.starts_with?(key, "result:my_repo:")
    end

    test "generates same key for list params wrapped in __params__ vs direct list" do
      sql = "SELECT * FROM users WHERE id = $1"
      opts = [data_repo: "my_repo"]

      wrapped_params = %{__params__: [123]}
      key1 = Key.result(sql, wrapped_params, opts)

      params = [123]
      key2 = Key.result(sql, params, opts)

      assert key1 == key2
    end

    test "generates different keys for map vars vs list params with same values" do
      sql = "SELECT * FROM users WHERE id = $1"
      opts = [data_repo: "my_repo"]

      vars = %{"id" => 123}
      key1 = Key.result(sql, vars, opts)

      params = [123]
      key2 = Key.result(sql, params, opts)

      assert key1 != key2
    end

    test "uses default search_path when not provided" do
      sql = "SELECT * FROM users WHERE id = $1"
      bound_vars = %{"1" => 123}
      opts = [data_repo: "my_repo"]

      key = Key.result(sql, bound_vars, opts)

      assert String.starts_with?(key, "result:my_repo:")
    end
  end

  describe "key format and structure" do
    test "result keys follow expected format pattern" do
      sql = "SELECT * FROM test"
      bound_vars = %{"1" => "test"}
      opts = [data_repo: "test_repo"]

      key = Key.result(sql, bound_vars, opts)

      assert Regex.match?(~r/^result:[^:]+:[a-f0-9]{64}$/, key)
    end

    test "keys use SHA256 hashes (64 hex characters)" do
      sql = "SELECT test"
      opts = [data_repo: "repo"]

      result_key = Key.result(sql, %{}, opts)

      [_, _, result_hash] = String.split(result_key, ":")

      assert String.length(result_hash) == 64
      assert Regex.match?(~r/^[a-f0-9]+$/, result_hash)
    end

    test "keys are case-insensitive (lowercase hex)" do
      sql = "SELECT test"
      opts = [data_repo: "repo"]

      key = Key.result(sql, %{}, opts)
      hash = key |> String.split(":") |> List.last()

      refute String.contains?(hash, "A")
      refute String.contains?(hash, "B")
      refute String.contains?(hash, "C")
      refute String.contains?(hash, "D")
      refute String.contains?(hash, "E")
      refute String.contains?(hash, "F")
    end
  end
end
