defmodule LotusTest do
  use Lotus.Case, async: true

  import Lotus.Fixtures

  alias Lotus.Config

  setup do
    setup_test_data()
    :ok
  end

  describe "repo/0" do
    test "returns the configured repo" do
      assert Lotus.repo() == Lotus.Test.Repo
    end
  end

  describe "list_queries/0" do
    test "returns empty list when no queries exist" do
      assert Lotus.list_queries() == []
    end

    test "returns all queries" do
      query1 = query_fixture(%{name: "Users Query"})
      query2 = query_fixture(%{name: "Posts Query"})

      queries = Lotus.list_queries()

      assert length(queries) == 2
      assert query1 in queries
      assert query2 in queries
    end
  end

  describe "get_query!/1" do
    test "returns query when found" do
      query = query_fixture(%{name: "Test Query"})

      result = Lotus.get_query!(query.id)

      assert result.id == query.id
      assert result.name == "Test Query"
    end

    test "raises when query not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Lotus.get_query!(999_999)
      end
    end
  end

  describe "create_query/1" do
    test "creates query with valid attributes" do
      attrs = %{
        name: "New Query",
        description: "A test query",
        query: %{sql: "SELECT * FROM test_users", params: []},
        tags: ["test", "users"]
      }

      assert {:ok, query} = Lotus.create_query(attrs)
      assert query.name == "New Query"
      assert query.description == "A test query"
      assert query.query == %{sql: "SELECT * FROM test_users", params: []}
      assert query.tags == ["test", "users"]
    end

    test "returns error with invalid attributes" do
      attrs = %{name: "", query: %{}}

      assert {:error, changeset} = Lotus.create_query(attrs)
      refute changeset.valid?
    end
  end

  describe "update_query/2" do
    test "updates query with valid attributes" do
      query = query_fixture(%{name: "Original Query"})
      attrs = %{name: "Updated Query"}

      assert {:ok, updated_query} = Lotus.update_query(query, attrs)
      assert updated_query.name == "Updated Query"
      assert updated_query.id == query.id
    end
  end

  describe "delete_query/1" do
    test "deletes existing query" do
      query = query_fixture(%{name: "To Delete"})

      assert {:ok, deleted_query} = Lotus.delete_query(query)
      assert deleted_query.id == query.id

      assert_raise Ecto.NoResultsError, fn ->
        Lotus.get_query!(query.id)
      end
    end
  end

  describe "run_query/2 with Query struct" do
    test "runs query with SQL and no params" do
      query =
        query_fixture(%{
          name: "Active Users Query",
          query: %{sql: "SELECT name, email FROM test_users WHERE active = true ORDER BY name"}
        })

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 2

      rows = result.rows
      assert length(rows) == 2
      assert ["Hunter S. Thompson", "hunter@gonzo.net"] in rows
      assert ["Jack Kerouac", "jack@ontheroad.com"] in rows
    end

    test "runs query with SQL and params" do
      query =
        query_fixture(%{
          name: "Users by Age Query",
          query: %{
            sql: "SELECT name, age FROM test_users WHERE age > $1 ORDER BY age DESC",
            params: [40]
          }
        })

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 2

      rows = result.rows
      assert length(rows) == 2
      assert ["Charles Bukowski", 73] in rows
      assert ["Jack Kerouac", 47] in rows
    end

    test "handles query with nil params" do
      query =
        query_fixture(%{
          name: "Count Query",
          query: %{
            sql: "SELECT count(*) as total FROM test_users"
          }
        })

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 1
      assert result.rows == [[3]]
    end

    test "handles query with empty params" do
      query =
        query_fixture(%{
          name: "Simple Query",
          query: %{
            sql: "SELECT 1 as result",
            params: []
          }
        })

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "passes options through" do
      query =
        query_fixture(%{
          name: "Simple Query with Options",
          query: %{sql: "SELECT 1 as result"}
        })

      opts = [timeout: 5000]
      assert {:ok, result} = Lotus.run_query(query, opts)
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "handles SQL errors" do
      query =
        query_fixture(%{
          name: "Error Query",
          query: %{sql: "SELECT invalid_column FROM nonexistent_table"}
        })

      assert {:error, error} = Lotus.run_query(query)
      assert error =~ "relation \"nonexistent_table\" does not exist"
    end
  end

  describe "run_query/2 with query ID" do
    test "gets query by ID and runs it" do
      query =
        query_fixture(%{
          name: "ID Query",
          query: %{sql: "SELECT name FROM test_users WHERE active = false"}
        })

      assert {:ok, result} = Lotus.run_query(query.id)
      assert result.num_rows == 1
      assert result.rows == [["Charles Bukowski"]]
    end

    test "passes options through" do
      query =
        query_fixture(%{
          name: "ID with Options Query",
          query: %{sql: "SELECT 1 as result"}
        })

      opts = [timeout: 5000]
      assert {:ok, result} = Lotus.run_query(query.id, opts)
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "raises when query ID not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Lotus.run_query(999_999)
      end
    end
  end

  describe "run_sql/3" do
    test "runs SQL directly with no params" do
      sql = "SELECT name FROM test_users WHERE active = true ORDER BY name"

      assert {:ok, result} = Lotus.run_sql(sql)
      assert result.num_rows == 2
      assert result.rows == [["Hunter S. Thompson"], ["Jack Kerouac"]]
    end

    test "runs SQL with params" do
      sql = "SELECT name, age FROM test_users WHERE age > $1 AND active = $2 ORDER BY name"
      params = [30, true]

      assert {:ok, result} = Lotus.run_sql(sql, params)
      assert result.num_rows == 2
      assert ["Hunter S. Thompson", 37] in result.rows
      assert ["Jack Kerouac", 47] in result.rows
    end

    test "runs SQL with params and options" do
      sql = "SELECT count(*) FROM test_users"
      params = []
      opts = [timeout: 10_000]

      assert {:ok, result} = Lotus.run_sql(sql, params, opts)
      assert result.num_rows == 1
      assert result.rows == [[3]]
    end

    test "handles SQL errors" do
      sql = "SELECT * FROM nonexistent_table"

      assert {:error, error} = Lotus.run_sql(sql)
      assert error =~ "relation \"nonexistent_table\" does not exist"
    end
  end

  describe "configuration delegates" do
    test "primary_key_type/0 delegates to Config.primary_key_type/0" do
      assert Lotus.primary_key_type() == Config.primary_key_type()
    end

    test "foreign_key_type/0 delegates to Config.foreign_key_type/0" do
      assert Lotus.foreign_key_type() == Config.foreign_key_type()
    end

    test "unique_names?/0 delegates to Config.unique_names?/0" do
      assert Lotus.unique_names?() == Config.unique_names?()
    end
  end
end
