defmodule Lotus.AI.Tools.SchemaToolsTest do
  use Lotus.AICase, async: true

  alias Lotus.AI.Tools.SchemaTools

  describe "list_tables/1" do
    test "returns JSON-encoded table list for schema-aware database" do
      stub(Lotus.Schema, :list_tables, fn _source ->
        {:ok, table_list()}
      end)

      assert {:ok, json} = SchemaTools.list_tables("postgres")
      assert {:ok, decoded} = Lotus.JSON.decode(json)
      assert decoded["tables"] == ["users", "posts", "comments", "events"]
    end

    test "returns JSON-encoded table list for schema-less database" do
      stub(Lotus.Schema, :list_tables, fn _source ->
        {:ok, sqlite_table_list()}
      end)

      assert {:ok, json} = SchemaTools.list_tables("sqlite")
      assert {:ok, decoded} = Lotus.JSON.decode(json)
      assert decoded["tables"] == ["users", "posts", "comments"]
    end

    test "returns error when schema introspection fails" do
      stub(Lotus.Schema, :list_tables, fn _source ->
        {:error, "Connection failed"}
      end)

      assert {:error, "Connection failed"} = SchemaTools.list_tables("postgres")
    end
  end

  describe "get_table_schema/2" do
    test "returns JSON-encoded column schema" do
      stub(Lotus.Schema, :get_table_schema, fn _source, _table ->
        {:ok, users_table_schema()}
      end)

      assert {:ok, json} = SchemaTools.get_table_schema("postgres", "users")
      assert {:ok, decoded} = Lotus.JSON.decode(json)

      assert decoded["table"] == "users"
      assert length(decoded["columns"]) == 4

      [id_col | _] = decoded["columns"]
      assert id_col["name"] == "id"
      assert id_col["type"] == "integer"
      assert id_col["nullable"] == false
      assert id_col["primary_key"] == true
    end

    test "handles nullable and non-primary-key columns" do
      stub(Lotus.Schema, :get_table_schema, fn _source, _table ->
        {:ok, users_table_schema()}
      end)

      assert {:ok, json} = SchemaTools.get_table_schema("postgres", "users")
      assert {:ok, decoded} = Lotus.JSON.decode(json)

      status_col = Enum.find(decoded["columns"], &(&1["name"] == "status"))
      assert status_col["nullable"] == true
      assert status_col["primary_key"] == false
    end

    test "returns error when table not found" do
      stub(Lotus.Schema, :get_table_schema, fn _source, _table ->
        {:error, "Table not found"}
      end)

      assert {:error, "Table not found"} = SchemaTools.get_table_schema("postgres", "unknown")
    end
  end

  describe "list_tables_metadata/0" do
    test "returns tool metadata" do
      metadata = SchemaTools.list_tables_metadata()

      assert metadata.name == "list_tables"
      assert metadata.description =~ "Get list of all available tables"
      assert metadata.parameters == %{}
    end
  end

  describe "get_table_schema_metadata/0" do
    test "returns tool metadata" do
      metadata = SchemaTools.get_table_schema_metadata()

      assert metadata.name == "get_table_schema"
      assert metadata.description =~ "Get column details"
      assert metadata.parameters.table_name.type == "string"
      assert metadata.parameters.table_name.required == true
    end
  end
end
