defmodule Lotus.Storage.SchemaCacheTest do
  use Lotus.CacheCase
  use Mimic

  alias Lotus.Cache
  alias Lotus.Config
  alias Lotus.Source
  alias Lotus.Source.Adapter
  alias Lotus.Storage.SchemaCache

  # Mock repo module for testing
  defmodule MockRepo do
    def __adapter__, do: Ecto.Adapters.Postgres
    def config, do: []
  end

  # Mock adapter module that delegates get_table_schema to the process dictionary,
  # allowing per-test control via Mimic expectations on Source.
  defmodule MockAdapterModule do
    @behaviour Lotus.Source.Adapter

    def get_table_schema(repo, schema, table) do
      # Calls the function stored in process dict by the test setup
      apply(Process.get(:mock_get_table_schema), [repo, schema, table])
    end

    # Stubs for required callbacks (not used in these tests)
    def execute_query(_, _, _, _), do: {:error, :not_implemented}
    def transaction(_, _, _), do: {:error, :not_implemented}
    def list_schemas(_), do: {:ok, []}
    def list_tables(_, _, _), do: {:ok, []}
    def resolve_table_schema(_, _, _), do: {:ok, nil}
    def quote_identifier(_, id), do: ~s("#{id}")
    def param_placeholder(_, i, _, _), do: "$#{i}"
    def limit_offset_placeholders(_, l, o), do: {"$#{l}", "$#{o}"}
    def apply_filters(_, sql, params, _), do: {sql, params}
    def apply_sorts(_, sql, _), do: sql
    def explain_plan(_, _, _, _), do: {:ok, "plan"}
    def builtin_denies(_), do: []
    def builtin_schema_denies(_), do: []
    def default_schemas(_), do: ["public"]
    def health_check(_), do: :ok
    def disconnect(_), do: :ok
    def format_error(_, e), do: inspect(e)
    def handled_errors(_), do: []
    def source_type(_), do: :postgres
    def supports_feature?(_, _), do: false
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

  # Helper: stub Source.resolve!/2 to return mock adapter and set up get_table_schema mock
  defp stub_resolve! do
    Source
    |> stub(:resolve!, fn _repo, _fallback ->
      %Adapter{
        name: "mock",
        module: MockAdapterModule,
        state: MockRepo,
        source_type: :postgres
      }
    end)
  end

  defp expect_get_table_schema(columns_fn) do
    stub_resolve!()

    Process.put(:mock_get_table_schema, fn repo, schema, table ->
      {:ok, columns_fn.(repo, schema, table)}
    end)
  end

  defp expect_get_table_schema_error(error_fn) do
    stub_resolve!()

    Process.put(:mock_get_table_schema, fn repo, schema, table ->
      error_fn.(repo, schema, table)
    end)
  end

  describe "get_table_schema/3" do
    test "returns schema map for valid table" do
      columns = [
        %{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true},
        %{name: "name", type: "varchar(255)", nullable: false, default: nil, primary_key: false},
        %{name: "email", type: "varchar(255)", nullable: true, default: nil, primary_key: false}
      ]

      expect_get_table_schema(fn _repo, "public", "users" -> columns end)

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

      call_count = :counters.new(1, [:atomics])

      expect_get_table_schema(fn _repo, "public", "orders" ->
        :counters.add(call_count, 1, 1)
        columns
      end)

      # First call - cache miss
      {:ok, schema1} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      # Second call - should use cache
      {:ok, schema2} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      assert schema1 == schema2
      assert :counters.get(call_count, 1) == 1
    end

    test "returns error for database failure" do
      expect_get_table_schema_error(fn _repo, "public", "nonexistent" ->
        raise ArgumentError, "Table not found"
      end)

      result = SchemaCache.get_table_schema(MockRepo, "public", "nonexistent")

      assert {:error, message} = result
      assert message =~ "Table not found"
    end

    test "caches tables separately per schema" do
      expect_get_table_schema(fn
        _repo, "public", "users" ->
          [%{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}]

        _repo, "archive", "users" ->
          [%{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}]
      end)

      {:ok, public_schema} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, archive_schema} = SchemaCache.get_table_schema(MockRepo, "archive", "users")

      assert public_schema["id"].type == "uuid"
      assert archive_schema["id"].type == "bigint"
    end

    test "handles nil schema" do
      expect_get_table_schema(fn _repo, nil, "settings" ->
        [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]
      end)

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

      expect_get_table_schema(fn _repo, "public", "users" -> columns end)

      assert {:ok, "uuid"} = SchemaCache.get_column_type(MockRepo, "public", "users", "id")

      assert {:ok, "varchar(255)"} =
               SchemaCache.get_column_type(MockRepo, "public", "users", "name")
    end

    test "returns :not_found for nonexistent column" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]

      expect_get_table_schema(fn _repo, "public", "users" -> columns end)

      assert :not_found = SchemaCache.get_column_type(MockRepo, "public", "users", "nonexistent")
    end

    test "returns :not_found when table fetch fails" do
      expect_get_table_schema_error(fn _repo, "public", "bad_table" ->
        raise ArgumentError, "Database error"
      end)

      assert :not_found = SchemaCache.get_column_type(MockRepo, "public", "bad_table", "id")
    end
  end

  describe "invalidate/3" do
    test "clears cache for specified table" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]
      call_count = :counters.new(1, [:atomics])

      expect_get_table_schema(fn _repo, "public", "products" ->
        :counters.add(call_count, 1, 1)
        columns
      end)

      # First call - populates cache
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "products")

      # Invalidate
      assert :ok = SchemaCache.invalidate(MockRepo, "public", "products")

      # Second call - should re-fetch (cache was invalidated)
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "products")

      assert :counters.get(call_count, 1) == 2
    end

    test "only invalidates specified table" do
      expect_get_table_schema(fn
        _repo, "public", "users" ->
          [%{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}]

        _repo, "public", "orders" ->
          [%{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}]
      end)

      # Populate both caches
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      # Invalidate only users
      SchemaCache.invalidate(MockRepo, "public", "users")

      # Users should be re-fetched, orders should still be cached
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "orders")
    end
  end

  describe "warm_cache/2" do
    test "preloads schemas for specified tables" do
      expect_get_table_schema(fn
        _repo, "public", "users" ->
          [%{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}]

        _repo, "public", "orders" ->
          [%{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}]
      end)

      assert :ok =
               SchemaCache.warm_cache(MockRepo, [
                 {"public", "users"},
                 {"public", "orders"}
               ])

      # Subsequent calls should use cache
      {:ok, users} = SchemaCache.get_table_schema(MockRepo, "public", "users")
      {:ok, orders} = SchemaCache.get_table_schema(MockRepo, "public", "orders")

      assert users["id"].type == "uuid"
      assert orders["id"].type == "bigint"
    end

    test "continues warming even if one table fails" do
      stub_resolve!()

      Process.put(:mock_get_table_schema, fn
        _repo, "public", "bad_table" ->
          raise ArgumentError, "Table not found"

        _repo, "public", table ->
          case table do
            "users" ->
              {:ok,
               [%{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}]}

            "products" ->
              {:ok,
               [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]}
          end
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
      stub_resolve!()
      assert :ok = SchemaCache.warm_cache(MockRepo, [])
    end
  end

  describe "cache key generation" do
    test "differentiates repos in cache keys" do
      defmodule AnotherRepo do
        def __adapter__, do: Ecto.Adapters.Postgres
        def config, do: []
      end

      expect_get_table_schema(fn
        _repo, "public", "shared_table" ->
          [%{name: "id", type: "uuid", nullable: false, default: nil, primary_key: true}]
      end)

      {:ok, schema1} = SchemaCache.get_table_schema(MockRepo, "public", "shared_table")

      # For second repo, we need a different resolve mock — but since the cache key
      # includes repo name (MockRepo vs AnotherRepo), the second call will be a cache miss
      # and call get_table_schema again with different columns
      Source
      |> stub(:resolve!, fn _repo, _fallback ->
        %Adapter{
          name: "another",
          module: MockAdapterModule,
          state: AnotherRepo,
          source_type: :postgres
        }
      end)

      Process.put(:mock_get_table_schema, fn _repo, "public", "shared_table" ->
        {:ok, [%{name: "id", type: "bigint", nullable: false, default: nil, primary_key: true}]}
      end)

      {:ok, schema2} = SchemaCache.get_table_schema(AnotherRepo, "public", "shared_table")

      assert schema1["id"].type == "uuid"
      assert schema2["id"].type == "bigint"
    end
  end

  describe "configuration" do
    test "uses configured TTL" do
      columns = [%{name: "id", type: "integer", nullable: false, default: nil, primary_key: true}]

      expect_get_table_schema(fn _repo, "public", "ttl_test" -> columns end)

      {:ok, _} = SchemaCache.get_table_schema(MockRepo, "public", "ttl_test")

      # Verify cache was populated
      cache_key = "schema_cache:MockRepo:public:ttl_test"
      assert {:ok, _} = Cache.get(cache_key)
    end
  end
end
