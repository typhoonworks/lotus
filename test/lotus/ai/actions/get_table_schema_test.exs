defmodule Lotus.AI.Actions.GetTableSchemaTest do
  use Lotus.AICase, async: true

  import Lotus.AIFixtures

  alias Lotus.AI.Actions.GetTableSchema

  describe "run/2" do
    test "returns column details for a table" do
      stub(Lotus.Schema, :get_table_schema, fn _source, _table ->
        {:ok, users_table_schema()}
      end)

      assert {:ok, result} =
               GetTableSchema.run(%{data_source: "postgres", table_name: "users"}, %{})

      assert result.table == "users"
      assert length(result.columns) == 4

      [id_col | _] = result.columns
      assert id_col.name == "id"
      assert id_col.type == "integer"
      assert id_col.nullable == false
      assert id_col.primary_key == true
    end

    test "parses schema-qualified table names" do
      expect(Lotus.Schema, :get_table_schema, fn _source, table, opts ->
        assert table == "customers"
        assert opts[:schema] == "reporting"
        {:ok, [%{name: "id", type: "integer", nullable: false, primary_key: true}]}
      end)

      assert {:ok, result} =
               GetTableSchema.run(
                 %{data_source: "postgres", table_name: "reporting.customers"},
                 %{}
               )

      assert result.table == "reporting.customers"
    end

    test "rejects invalid table names" do
      assert {:error, msg} =
               GetTableSchema.run(
                 %{data_source: "postgres", table_name: "users\"; DROP TABLE users--"},
                 %{}
               )

      assert msg =~ "Invalid table name"
    end

    test "returns error when table not found" do
      stub(Lotus.Schema, :get_table_schema, fn _source, _table ->
        {:error, "Table not found"}
      end)

      assert {:error, "Table not found"} =
               GetTableSchema.run(%{data_source: "postgres", table_name: "unknown"}, %{})
    end
  end

  describe "tool metadata" do
    test "exposes name, description, and schema" do
      assert GetTableSchema.name() == "get_table_schema"
      assert GetTableSchema.description() =~ "column details"
      assert Keyword.has_key?(GetTableSchema.schema(), :table_name)
      assert Keyword.has_key?(GetTableSchema.schema(), :data_source)
    end
  end
end
