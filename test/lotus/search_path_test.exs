defmodule Lotus.SearchPathTest do
  use Lotus.Case, async: true

  alias Lotus.Storage

  @moduletag :postgres

  describe "search_path functionality" do
    test "stored query with search_path resolves unqualified table names" do
      # Create a query that references customers table without schema qualification
      {:ok, query} =
        Storage.create_query(%{
          name: "Unqualified Customers Query",
          statement: "SELECT COUNT(*) FROM customers",
          search_path: "reporting, public",
          data_repo: "postgres"
        })

      # The query should execute successfully using the search_path to find reporting.customers
      assert {:ok, result} = Lotus.run_query(query)
      assert %Lotus.Result{columns: ["count"], rows: [[0]]} = result
    end

    test "runtime search_path override resolves unqualified table names" do
      # Execute ad-hoc query with search_path
      sql = "SELECT COUNT(*) FROM customers"

      assert {:ok, result} =
               Lotus.run_sql(sql, [], repo: "postgres", search_path: "reporting, public")

      assert %Lotus.Result{columns: ["count"], rows: [[0]]} = result
    end

    test "runtime search_path overrides stored query search_path" do
      {:ok, query} =
        Storage.create_query(%{
          name: "Override Test",
          statement: "SELECT COUNT(*) FROM customers",
          data_repo: "postgres"
        })

      assert {:ok, result} = Lotus.run_query(query, search_path: "reporting, public")
      assert %Lotus.Result{columns: ["count"], rows: [[0]]} = result
    end

    test "query fails without search_path when table is in non-default schema" do
      sql = "SELECT COUNT(*) FROM customers"

      assert {:error, error} = Lotus.run_sql(sql, [], repo: "postgres")
      assert error =~ "relation \"customers\" does not exist"
    end

    test "preflight honors search_path for relation visibility checks" do
      sql = "SELECT * FROM customers WHERE email = $1"

      assert {:ok, _result} =
               Lotus.run_sql(sql, ["test@example.com"],
                 repo: "postgres",
                 search_path: "reporting, public"
               )
    end
  end

  describe "SQLite ignores search_path gracefully" do
    @tag :sqlite
    test "search_path option is ignored for SQLite repos" do
      sql = "SELECT COUNT(*) FROM products"

      assert {:ok, result} =
               Lotus.run_sql(sql, [], repo: "sqlite", search_path: "ignored_schema")

      assert %Lotus.Result{columns: ["COUNT(*)"], rows: [[0]]} = result
    end
  end
end
