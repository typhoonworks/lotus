defmodule Lotus.StorageTest do
  use Lotus.Case, async: true
  use Mimic

  import Lotus.Fixtures

  alias Lotus.Storage

  describe "list_queries/1" do
    test "returns empty list when no queries exist" do
      assert Storage.list_queries() == []
    end

    test "returns all queries" do
      query1 = query_fixture(%{name: "Users Query", tags: ["users"]})
      query2 = query_fixture(%{name: "Posts Query", tags: ["posts"]})

      queries = Storage.list_queries()

      assert length(queries) == 2
      assert query1 in queries
      assert query2 in queries
    end
  end

  describe "list_queries_by/1" do
    setup do
      query1 =
        query_fixture(%{
          name: "Active Users",
          tags: ["users", "analytics"]
        })

      query2 =
        query_fixture(%{
          name: "User Reports",
          tags: ["reporting", "users"]
        })

      query3 =
        query_fixture(%{
          name: "Product Analytics",
          tags: ["analytics", "products"]
        })

      {:ok, queries: %{users_analytics: query1, user_reports: query2, product_analytics: query3}}
    end

    test "returns all queries when no filters provided", %{queries: queries} do
      result = Storage.list_queries_by([])

      assert length(result) == 3
      assert queries.users_analytics in result
      assert queries.user_reports in result
      assert queries.product_analytics in result
    end

    test "filters by single tag", %{queries: queries} do
      result = Storage.list_queries_by(tags: ["analytics"])

      assert length(result) == 2
      assert queries.users_analytics in result
      assert queries.product_analytics in result
      refute queries.user_reports in result
    end

    test "filters by multiple tags (OR logic)", %{queries: queries} do
      result = Storage.list_queries_by(tags: ["reporting", "products"])

      assert length(result) == 2
      assert queries.user_reports in result
      assert queries.product_analytics in result
      refute queries.users_analytics in result
    end

    test "filters by search term (case insensitive)", %{queries: queries} do
      result = Storage.list_queries_by(search: "user")

      assert length(result) == 2
      assert queries.users_analytics in result
      assert queries.user_reports in result
      refute queries.product_analytics in result
    end

    test "combines tag and search filters", %{queries: queries} do
      result = Storage.list_queries_by(tags: ["analytics"], search: "user")

      assert length(result) == 1
      assert queries.users_analytics in result
      refute queries.user_reports in result
      refute queries.product_analytics in result
    end

    test "returns empty list when no matches found" do
      query_fixture(%{name: "Test Query", tags: ["test"]})

      result = Storage.list_queries_by(tags: ["nonexistent"])
      assert result == []

      result = Storage.list_queries_by(search: "nonexistent")
      assert result == []
    end

    test "handles empty tags list" do
      query = query_fixture(%{name: "Test Query", tags: ["test"]})

      result = Storage.list_queries_by(tags: [])
      assert length(result) == 4
      assert query in result
    end
  end

  describe "get_query!/2" do
    test "returns query when found" do
      query = query_fixture(%{name: "Test Query"})

      result = Storage.get_query!(query.id)

      assert result.id == query.id
      assert result.name == "Test Query"
    end

    test "raises when query not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Storage.get_query!(999_999)
      end
    end
  end

  describe "create_query/2" do
    test "creates query with valid attributes" do
      attrs = %{
        name: "New Query",
        description: "A test query",
        query: %{sql: "SELECT * FROM users", params: []},
        tags: ["test", "users"]
      }

      assert {:ok, query} = Storage.create_query(attrs)
      assert query.name == "New Query"
      assert query.description == "A test query"
      assert query.query == %{sql: "SELECT * FROM users", params: []}
      assert query.tags == ["test", "users"]
      assert query.id
      assert query.inserted_at
      assert query.updated_at
    end

    test "creates query with minimal attributes" do
      attrs = %{
        name: "Minimal Query",
        query: %{sql: "SELECT 1"}
      }

      assert {:ok, query} = Storage.create_query(attrs)
      assert query.name == "Minimal Query"
      assert query.description == nil
      assert query.query == %{sql: "SELECT 1"}
      assert query.tags == []
    end

    test "returns error with invalid attributes" do
      attrs = %{name: "", query: %{}}

      assert {:error, changeset} = Storage.create_query(attrs)
      refute changeset.valid?

      assert %{
               name: ["can't be blank"],
               query: ["must include sql (string) and optionally params (list)"]
             } = errors_on(changeset)
    end

    test "returns error when required fields missing" do
      attrs = %{}

      assert {:error, changeset} = Storage.create_query(attrs)
      refute changeset.valid?
      assert %{name: ["can't be blank"], query: ["can't be blank"]} = errors_on(changeset)
    end

    test "normalizes tags" do
      attrs = %{
        name: "Tag Test",
        query: %{sql: "SELECT 1"},
        tags: ["  Analytics  ", "REPORTING", "analytics", "", "reporting"]
      }

      assert {:ok, query} = Storage.create_query(attrs)
      assert query.tags == ["analytics", "reporting"]
    end
  end

  describe "update_query/3" do
    setup do
      {:ok,
       query:
         query_fixture(%{
           name: "Original Query",
           description: "Original description",
           query: %{sql: "SELECT * FROM users"},
           tags: ["original"]
         })}
    end

    test "updates query with valid attributes", %{query: query} do
      attrs = %{
        name: "Updated Query",
        description: "Updated description",
        tags: ["updated", "test"]
      }

      assert {:ok, updated_query} = Storage.update_query(query, attrs)
      assert updated_query.id == query.id
      assert updated_query.name == "Updated Query"
      assert updated_query.description == "Updated description"
      assert updated_query.tags == ["updated", "test"]
      assert updated_query.query == %{sql: "SELECT * FROM users"}
    end

    test "updates only provided attributes", %{query: query} do
      attrs = %{name: "New Name Only"}

      assert {:ok, updated_query} = Storage.update_query(query, attrs)
      assert updated_query.name == "New Name Only"
      assert updated_query.description == "Original description"
      assert updated_query.tags == ["original"]
    end

    test "updates query payload", %{query: query} do
      attrs = %{query: %{sql: "SELECT count(*) FROM users", params: []}}

      assert {:ok, updated_query} = Storage.update_query(query, attrs)
      assert updated_query.query == %{sql: "SELECT count(*) FROM users", params: []}
    end

    test "returns error with invalid attributes", %{query: query} do
      attrs = %{name: "", query: %{sql: ""}}

      assert {:error, changeset} = Storage.update_query(query, attrs)
      refute changeset.valid?

      assert %{
               name: ["can't be blank"],
               query: ["sql cannot be empty"]
             } = errors_on(changeset)
    end

    test "normalizes tags on update", %{query: query} do
      attrs = %{tags: ["  NEW  ", "tag", "NEW", ""]}

      assert {:ok, updated_query} = Storage.update_query(query, attrs)
      assert updated_query.tags == ["new", "tag"]
    end
  end

  describe "delete_query/2" do
    test "deletes existing query" do
      query = query_fixture(%{name: "To Delete"})

      assert {:ok, deleted_query} = Storage.delete_query(query)
      assert deleted_query.id == query.id

      assert_raise Ecto.NoResultsError, fn ->
        Storage.get_query!(query.id)
      end
    end
  end

  describe "run/2" do
    setup do
      Mimic.copy(Lotus)
      :ok
    end

    test "delegates to Lotus.run_query/2" do
      query =
        query_fixture(%{
          name: "Test Query",
          query: %{sql: "SELECT 1 as result"}
        })

      expected_result = {:ok, %{"result" => 1}}

      Lotus
      |> expect(:run_query, fn ^query, [] -> expected_result end)

      result = Storage.run(query)

      assert result == expected_result
    end

    test "passes options through to Lotus.run_query/2" do
      query =
        query_fixture(%{
          name: "Test Query",
          query: %{sql: "SELECT 1 as result"}
        })

      opts = [statement_timeout_ms: 3000, prefix: "analytics"]
      expected_result = {:ok, %{"result" => 1}}

      Lotus
      |> expect(:run_query, fn ^query, ^opts -> expected_result end)

      result = Storage.run(query, opts)

      assert result == expected_result
    end

    test "handles error responses from Lotus.run_query/2" do
      query =
        query_fixture(%{
          name: "Failing Query",
          query: %{sql: "SELECT invalid"}
        })

      expected_error = {:error, "Invalid SQL"}

      Lotus
      |> expect(:run_query, fn ^query, [] -> expected_error end)

      result = Storage.run(query)

      assert result == expected_error
    end
  end
end
