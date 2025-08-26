defmodule Lotus.SchemaTest do
  use Lotus.Case

  alias Lotus.Schema

  describe "list_tables/1" do
    @tag :sqlite
    test "lists tables from a data repo by name" do
      {:ok, tables} = Schema.list_tables("sqlite")

      assert is_list(tables)
      assert "orders" in tables
      assert "order_items" in tables
      assert "products" in tables
    end

    @tag :sqlite
    test "lists tables from a repo module directly" do
      {:ok, tables} = Schema.list_tables(Lotus.Test.SqliteRepo)

      assert is_list(tables)
      assert "orders" in tables
      assert "order_items" in tables
      assert "products" in tables
    end

    test "returns error for non-existent repo name" do
      assert_raise ArgumentError, ~r/Data repo 'nonexistent' not configured/, fn ->
        Schema.list_tables("nonexistent")
      end
    end

    @tag :sqlite
    test "filters out system tables" do
      {:ok, tables} = Schema.list_tables(Lotus.Test.SqliteRepo)

      refute Enum.any?(tables, &String.starts_with?(&1, "sqlite_"))
      refute Enum.any?(tables, &String.starts_with?(&1, "lotus_"))
    end
  end

  describe "get_table_schema/2" do
    @tag :sqlite
    test "gets schema for a table in SQLite" do
      {:ok, schema} = Schema.get_table_schema("sqlite", "products")

      assert is_list(schema)
      assert length(schema) > 0

      column_names = Enum.map(schema, & &1.name)
      assert "id" in column_names
      assert "name" in column_names
      assert "price" in column_names
      assert "stock_quantity" in column_names

      id_col = Enum.find(schema, &(&1.name == "id"))
      assert id_col.primary_key == true
      assert id_col.nullable == true

      name_col = Enum.find(schema, &(&1.name == "name"))
      assert name_col.type =~ "TEXT" or name_col.type =~ "VARCHAR"
      assert name_col.nullable == false

      price_col = Enum.find(schema, &(&1.name == "price"))
      assert price_col.type =~ "DECIMAL" or price_col.type =~ "NUMERIC"
    end

    @tag :sqlite
    test "gets schema for a table with foreign keys" do
      {:ok, schema} = Schema.get_table_schema(Lotus.Test.SqliteRepo, "order_items")

      column_names = Enum.map(schema, & &1.name)
      assert "order_id" in column_names
      assert "product_id" in column_names
      assert "quantity" in column_names
      assert "unit_price" in column_names
    end

    @tag :sqlite
    test "returns error for non-existent table" do
      {:ok, schema} = Schema.get_table_schema(Lotus.Test.SqliteRepo, "non_existent_table")

      assert schema == []
    end

    @tag :sqlite
    test "includes default values in schema" do
      {:ok, schema} = Schema.get_table_schema(Lotus.Test.SqliteRepo, "products")

      stock_quantity_col = Enum.find(schema, &(&1.name == "stock_quantity"))
      assert stock_quantity_col.default != nil
    end
  end

  describe "get_table_stats/2" do
    @tag :sqlite
    @tag :skip
    test "gets row count for a table" do
      insert_test_data(Lotus.Test.SqliteRepo)

      {:ok, stats} = Schema.get_table_stats("sqlite", "products")

      assert is_map(stats)
      assert Map.has_key?(stats, :row_count)
      assert stats.row_count >= 0
    end

    @tag :sqlite
    test "returns zero count for empty table" do
      {:ok, stats} = Schema.get_table_stats(Lotus.Test.SqliteRepo, "products")

      assert stats.row_count == 0
    end

    @tag :sqlite
    test "returns error for non-existent table" do
      {:error, error} = Schema.get_table_stats(Lotus.Test.SqliteRepo, "non_existent_table")

      assert error =~ "no such table" or error =~ "does not exist"
    end
  end

  describe "PostgreSQL adapter" do
    @tag :postgres
    test "lists tables from PostgreSQL repo" do
      {:ok, tables} = Schema.list_tables(Lotus.Test.Repo)

      assert is_list(tables)
      assert {"public", "test_users"} in tables
      assert {"public", "test_posts"} in tables
    end

    @tag :postgres
    test "gets PostgreSQL table schema with proper types" do
      {:ok, schema} = Schema.get_table_schema(Lotus.Test.Repo, "test_users")

      name_col = Enum.find(schema, &(&1.name == "name"))
      assert name_col.type =~ "character varying" or name_col.type =~ "varchar"

      id_col = Enum.find(schema, &(&1.name == "id"))
      assert id_col.type =~ "bigint" or id_col.type =~ "integer"
      assert id_col.primary_key == true
    end
  end

  describe "integration with Lotus module" do
    @tag :sqlite
    test "list_tables is accessible through main module" do
      {:ok, tables} = Lotus.list_tables("sqlite")

      assert is_list(tables)
      assert length(tables) > 0
    end

    @tag :sqlite
    test "get_table_schema is accessible through main module" do
      {:ok, schema} = Lotus.get_table_schema("sqlite", "products")

      assert is_list(schema)
      assert length(schema) > 0
    end

    @tag :sqlite
    test "get_table_stats is accessible through main module" do
      {:ok, stats} = Lotus.get_table_stats("sqlite", "products")

      assert is_map(stats)
      assert Map.has_key?(stats, :row_count)
    end
  end

  defp insert_test_data(repo) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    repo.query!("""
      INSERT INTO products (name, sku, description, price, stock_quantity, inserted_at, updated_at)
      VALUES
        ('Test Product 1', 'SKU001', 'Description 1', 19.99, 100, '#{now}', '#{now}'),
        ('Test Product 2', 'SKU002', 'Description 2', 29.99, 50, '#{now}', '#{now}'),
        ('Test Product 3', 'SKU003', 'Description 3', 39.99, 25, '#{now}', '#{now}')
    """)
  end
end
