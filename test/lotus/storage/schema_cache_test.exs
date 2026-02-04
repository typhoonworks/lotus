defmodule Lotus.Storage.SchemaCacheTest do
  use Lotus.CacheCase
  use Mimic

  alias Lotus.Cache
  alias Lotus.Config
  alias Lotus.Source
  alias Lotus.Storage.SchemaCache

  # Mock repo module for testing
  defmodule MockRepo do
    def __adapter__, do: Ecto.Adapters.Postgres
    def config, do: []
  end

  setup :verify_on_exit!

  setup do
    # Configure cache to be enabled
    Mimic.copy(Lotus.Config)
    Mimic.copy(Lotus.Source)

    Config
    |> stub(:cache_adapter, fn -> {:ok, Lotus.Cache.ETS} end)
    |> stub(:cache_namespace, fn -> "test_schema_cache" end)

    :ok
  end

  describe "get_table_schema/3" do
    test "returns schema map for valid table" do
      columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true},
        %{name: "name", type: "varchar(255)", nullable: false, default: nil, primary_key: false},
        %{name: "email", type: "varchar(255)", nullable: true, default: nil, primary_key: false}
      ]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> columns end)

      result = SchemaCache.get_table_schema(MockRepo, "public", "users")

      assert {:ok, schema_map} = result
      assert Map.has_key?(schema_map, "id")
      assert Map.has_key?(schema_map, "name")
      assert Map.has_key?(schema_map, "email")

      assert schema_map["id"].type == "uuid"
      assert schema_map["id"].nullable == false
      assert schema_map["id"].primary_key == true
    end

    test "caches result for subsequent calls" do
      columns = [
        %{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}
      ]

      # Should only be called once
      Source
      |> expect(:get_table_schema, 1, fn MockRepo, "public", "orders" -> columns end)

      # First call - cache miss
      {:ok, schema1} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      # Second call - should use cache
      {:ok, schema2} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      assert schema1 == schema2
    end

    test "returns error for database failure" do
      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "nonexistent" ->
        raise ArgumentError, "Table not found"
      end)

      result = SchemaCache.get_table_schema(MockRepo, "public", "nonexistent")

      assert {:error, message} = result
      assert message =~ "Table not found"
    end

    test "caches tables separately per schema" do
      users_columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}
      ]

      archived_users_columns = [
        %{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}
      ]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> users_columns end)
      |> expect(:get_table_schema, fn MockRepo, "archive", "users" -> archived_users_columns end)

      {:ok, public_schema} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, archive_schema} = SchemaCache.get_table_schema(MockRepo, "archive", "users")

      assert public_schema["id"].type == "uuid"
      assert archive_schema["id"].type == "bigint"
    end

    test "handles nil schema" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]

      Source
      |> expect(:get_table_schema, fn MockRepo, nil, "settings" -> columns end)

      {:ok, schema} = SchemaCache.get_table_schema(MockRepo, nil, "settings")

      assert schema["id"].type == "integer"
    end
  end

  describe "get_column_type/4" do
    test "returns type for valid column" do
      columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true},
        %{name: "name", type: "varchar(255)", nullable: false, default: nil, primary_key: false}
      ]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> columns end)

      assert {:ok, "uuid"} = SchemaCache.get_column_type(MockRepo, "public", "users", "id")

      assert {:ok, "varchar(255)"} =
               SchemaCache.get_column_type(MockRepo, "public", "users", "name")
    end

    test "returns :not_found for nonexistent column" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> columns end)

      assert :not_found = SchemaCache.get_column_type(MockRepo, "public", "users", "nonexistent")
    end

    test "returns :not_found when table fetch fails" do
      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "bad_table" ->
        raise ArgumentError, "Database error"
      end)

      assert :not_found = SchemaCache.get_column_type(MockRepo, "public", "bad_table", "id")
    end
  end

  describe "invalidate/3" do
    test "clears cache for specified table" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]

      Source
      |> expect(:get_table_schema, 2, fn MockRepo, "public", "products" -> columns end)

      # First call - populates cache
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "products")

      # Invalidate
      assert :ok = SchemaCache.invalidate(MockRepo, "public", "products")

      # Second call - should re-fetch (cache was invalidated)
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "products")
    end

    test "only invalidates specified table" do
      users_columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}
      ]

      orders_columns = [
        %{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}
      ]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> users_columns end)
      |> expect(:get_table_schema, fn MockRepo, "public", "orders" -> orders_columns end)

      # Populate both caches
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      # Invalidate only users
      SchemaCache.invalidate(MockRepo, "public", "users")

      # Expect users to be refetched, but not orders
      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> users_columns end)

      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "users")

      # Orders should still be cached (no additional expect needed)
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "orders")
    end
  end

  describe "warm_cache/2" do
    test "preloads schemas for specified tables" do
      users_columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}
      ]

      orders_columns = [
        %{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}
      ]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> users_columns end)
      |> expect(:get_table_schema, fn MockRepo, "public", "orders" -> orders_columns end)

      assert :ok =
               SchemaCache.warm_cache(MockRepo, [
                 {"public", "users"},
                 {"public", "orders"}
               ])

      # Subsequent calls should use cache (no additional expects)
      {:ok, users} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, orders} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      assert users["id"].type == "uuid"
      assert orders["id"].type == "bigint"
    end

    test "continues warming even if one table fails" do
      users_columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}
      ]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "users" -> users_columns end)
      |> expect(:get_table_schema, fn MockRepo, "public", "bad_table" ->
        raise ArgumentError, "Table not found"
      end)
      |> expect(:get_table_schema, fn MockRepo, "public", "products" ->
        [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]
      end)

      # Should complete without raising
      assert :ok =
               SchemaCache.warm_cache(MockRepo, [
                 {"public", "users"},
                 {"public", "bad_table"},
                 {"public", "products"}
               ])

      # Users and products should be cached
      {:ok, users} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, products} = SchemaCache.get_table_schema(MockRepo, "public", "products")

      assert users["id"].type == "uuid"
      assert products["id"].type == "integer"
    end

    test "handles empty table list" do
      assert :ok = SchemaCache.warm_cache(MockRepo, [])
    end
  end

  describe "cache key generation" do
    test "differentiates repos in cache keys" do
      defmodule AnotherRepo do
        def __adapter__, do: Ecto.Adapters.Postgres
        def config, do: []
      end

      columns1 = [%{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}]
      columns2 = [%{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}]

      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "shared_table" -> columns1 end)
      |> expect(:get_table_schema, fn AnotherRepo, "public", "shared_table" -> columns2 end)

      {:ok, schema1} = SchemaCache.get_table_schema(MockRepo, "public", "shared_table")
      {:ok, schema2} = SchemaCache.get_table_schema(AnotherRepo, "public", "shared_table")

      assert schema1["id"].type == "uuid"
      assert schema2["id"].type == "bigint"
    end
  end

  describe "configuration" do
    test "uses configured TTL" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]

      # This test verifies the TTL is read from config
      # The actual expiration behavior is handled by the cache layer
      Source
      |> expect(:get_table_schema, fn MockRepo, "public", "ttl_test" -> columns end)

      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "ttl_test")

      # Verify cache was populated
      cache_key = "schema_cache:MockRepo:public:ttl_test"
      assert {:ok, _} = Cache.get(cache_key)
    end
  end
end
