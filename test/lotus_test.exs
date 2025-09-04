defmodule LotusTest do
  use Lotus.Case, async: true

  import Lotus.Fixtures

  alias Lotus.Config

  setup do
    setup_test_data()
    :ok
  end

  describe "child_spec/1" do
    test "name is used as a default child id" do
      assert Supervisor.child_spec(Lotus, []).id == Lotus
      assert Supervisor.child_spec({Lotus, name: :foo}, []).id == :foo
    end
  end

  describe "start_link/1" do
    test "name can be an arbitrary term" do
      opts = [name: make_ref(), cache: nil]
      assert {:ok, _pid} = start_supervised({Lotus, opts})
    end

    test "supervisor_name must be unique" do
      sup_name = :lotus_test_sup
      opts = [supervisor_name: sup_name, cache: nil]

      {:ok, pid} = Lotus.start_link(opts)
      assert {:error, {:already_started, ^pid}} = Lotus.start_link(opts)
    end
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
      query1 = query_fixture(%{name: "Users Query", statement: "SELECT * FROM test_users"})
      query2 = query_fixture(%{name: "Posts Query", statement: "SELECT * FROM test_posts"})

      queries = Lotus.list_queries()

      assert length(queries) == 2
      assert query1 in queries
      assert query2 in queries
    end
  end

  describe "get_query!/1" do
    test "returns query when found" do
      query = query_fixture(%{name: "Test Query", statement: "SELECT 1"})

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

  describe "get_query/2" do
    test "returns query when found" do
      query = query_fixture(%{name: "Test Query"})

      result = Lotus.get_query(query.id)

      assert result.id == query.id
      assert result.name == "Test Query"
    end

    test "returns nil when query not found" do
      assert Lotus.get_query(999_999) == nil
    end
  end

  describe "create_query/1" do
    test "creates query with valid attributes" do
      attrs = %{
        name: "New Query",
        description: "A test query",
        statement: "SELECT * FROM test_users",
        variables: []
      }

      assert {:ok, query} = Lotus.create_query(attrs)
      assert query.name == "New Query"
      assert query.description == "A test query"
      assert query.statement == "SELECT * FROM test_users"
      assert query.variables == []
      assert query.data_repo == nil
    end

    test "creates query with data_repo" do
      attrs = %{
        name: "Analytics Query",
        statement: "SELECT COUNT(*) FROM page_views",
        data_repo: "sqlite"
      }

      assert {:ok, query} = Lotus.create_query(attrs)
      assert query.data_repo == "sqlite"
    end

    test "returns error with invalid attributes" do
      attrs = %{name: "", statement: ""}

      assert {:error, changeset} = Lotus.create_query(attrs)
      refute changeset.valid?
    end
  end

  describe "update_query/2" do
    test "updates query with valid attributes" do
      query = query_fixture(%{name: "Original Query", statement: "SELECT 1"})
      attrs = %{name: "Updated Query"}

      assert {:ok, updated_query} = Lotus.update_query(query, attrs)
      assert updated_query.name == "Updated Query"
      assert updated_query.id == query.id
    end
  end

  describe "delete_query/1" do
    test "deletes existing query" do
      query = query_fixture(%{name: "To Delete", statement: "SELECT 1"})

      assert {:ok, deleted_query} = Lotus.delete_query(query)
      assert deleted_query.id == query.id

      assert_raise Ecto.NoResultsError, fn ->
        Lotus.get_query!(query.id)
      end
    end
  end

  describe "run_query/2 with Query struct" do
    alias Lotus.Storage.{Query, QueryVariable}

    test "runs query with SQL and no vars" do
      query = %Query{
        name: "Active Users Query",
        statement: "SELECT name, email FROM test_users WHERE active = true ORDER BY name",
        variables: []
      }

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 2

      rows = result.rows
      assert ["Hunter S. Thompson", "hunter@gonzo.net"] in rows
      assert ["Jack Kerouac", "jack@ontheroad.com"] in rows
    end

    test "runs query using stored variable with default value" do
      query = %Query{
        name: "Users by Age Query",
        statement: "SELECT name, age FROM test_users WHERE age > {{min_age}} ORDER BY age DESC",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "40"}
        ]
      }

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 2

      rows = result.rows
      assert ["Charles Bukowski", 73] in rows
      assert ["Jack Kerouac", 47] in rows
    end

    test "runs query with runtime vars overriding defaults" do
      query = %Query{
        name: "Override Vars Query",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "20"}
        ]
      }

      # Override min_age = 50 at runtime
      assert {:ok, result} = Lotus.run_query(query, vars: %{"min_age" => 50})
      assert result.num_rows == 1
      assert result.rows == [["Charles Bukowski"]]
    end

    test "errors if required var is missing and no default" do
      query = %Query{
        name: "Missing Var Query",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number}
        ]
      }

      assert {:error, msg} = Lotus.run_query(query)
      assert msg =~ "Missing required variable"
    end

    test "errors with helpful message for invalid number conversion" do
      query = %Query{
        name: "Invalid Number Query",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "not_a_number"}
        ]
      }

      assert {:error, msg} = Lotus.run_query(query)
      assert msg =~ "Invalid number format: 'not_a_number' is not a valid number"
    end

    test "errors with helpful message for number with non-numeric characters" do
      query = %Query{
        name: "Invalid Number Query",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "25abc"}
        ]
      }

      assert {:error, msg} = Lotus.run_query(query)
      assert msg =~ "Invalid number format: '25abc' contains non-numeric characters"
    end

    test "errors with helpful message for invalid date conversion" do
      query = %Query{
        name: "Invalid Date Query",
        statement: "SELECT name FROM test_users WHERE created_at > {{start_date}}",
        variables: [
          %QueryVariable{name: "start_date", type: :date, default: "not_a_date"}
        ]
      }

      assert {:error, msg} = Lotus.run_query(query)
      assert msg =~ "Invalid date format: 'not_a_date' is not a valid ISO8601 date"
    end

    test "errors for common invalid date formats" do
      invalid_dates = [
        # US format
        "12/25/2023",
        # EU format
        "25/12/2023",
        # Dashed EU format
        "25-12-2023",
        # Dashed US format
        "12-25-2023",
        # YYYY/MM/DD
        "2023/12/25",
        # Named month
        "Dec 25, 2023",
        # Named month EU
        "25 Dec 2023",
        # Invalid day
        "2023-12-32",
        # Invalid month
        "2023-13-25",
        # Compact format
        "20231225",
        # Missing leading zeros
        "2023-2-5",
        # Empty string
        ""
      ]

      for invalid_date <- invalid_dates do
        query = %Query{
          name: "Invalid Date Query",
          statement: "SELECT name FROM test_users WHERE inserted_at > {{start_date}}",
          variables: [
            %QueryVariable{name: "start_date", type: :date, default: invalid_date}
          ]
        }

        assert {:error, msg} = Lotus.run_query(query)

        assert msg =~ "Invalid date format: '#{invalid_date}' is not a valid ISO8601 date",
               "Expected error for date format: #{invalid_date}"
      end
    end

    test "successfully parses valid ISO8601 date formats" do
      valid_dates = [
        # Standard ISO8601
        "2023-12-25",
        # New Year
        "2023-01-01",
        # End of year
        "2023-12-31"
      ]

      for valid_date <- valid_dates do
        query = %Query{
          name: "Valid Date Query",
          statement: "SELECT name FROM test_users WHERE inserted_at > {{start_date}}",
          variables: [
            %QueryVariable{name: "start_date", type: :date, default: valid_date}
          ]
        }

        assert {:ok, _result} = Lotus.run_query(query),
               "Should succeed for valid date format: #{valid_date}"
      end
    end

    test "successfully converts integer strings to integers" do
      query = %Query{
        name: "Integer Query",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "25"}
        ]
      }

      assert {:ok, _result} = Lotus.run_query(query)
    end

    test "successfully converts float strings to floats" do
      query = %Query{
        name: "Float Query",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "25.5"}
        ]
      }

      assert {:ok, _result} = Lotus.run_query(query)
    end

    test "runs query using mixed stored defaults (number) and runtime values (text)" do
      query = %Query{
        name: "Mixed defaults and overrides",
        statement: """
        SELECT name, age
        FROM test_users
        WHERE age > {{min_age}} AND name = {{name}}
        """,
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "30"},
          %QueryVariable{name: "name", type: :text, default: "Jack Kerouac"}
        ]
      }

      # default min_age=30 & name=Jack Kerouac → 1 row
      assert {:ok, r1} = Lotus.run_query(query)
      assert r1.rows == [["Jack Kerouac", 47]]

      # override only the text var
      assert {:ok, r2} = Lotus.run_query(query, vars: %{"name" => "Hunter S. Thompson"})
      assert r2.rows == [["Hunter S. Thompson", 37]]

      # override the number too
      assert {:ok, r3} =
               Lotus.run_query(query, vars: %{"name" => "Hunter S. Thompson", "min_age" => 38})

      assert r3.rows == []
    end

    test "passes options through" do
      query = %Query{
        name: "Simple Query with Options",
        statement: "SELECT 1 as result",
        variables: []
      }

      opts = [timeout: 5000]
      assert {:ok, result} = Lotus.run_query(query, opts)
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "handles SQL errors" do
      query = %Query{
        name: "Error Query",
        statement: "SELECT invalid_column FROM nonexistent_table",
        variables: []
      }

      assert {:error, error} = Lotus.run_query(query)
      assert error =~ "relation \"nonexistent_table\" does not exist"
    end

    test "uses stored data_repo when specified" do
      query = %Query{
        name: "Test Data Query",
        statement: "SELECT 1 as result",
        variables: [],
        data_repo: "postgres"
      }

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "runtime repo option overrides stored data_repo" do
      query = %Query{
        name: "Override Test Query",
        statement: "SELECT 1 as result",
        variables: [],
        data_repo: "sqlite"
      }

      assert {:ok, result} = Lotus.run_query(query, repo: "postgres")
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end

    test "falls back to default repo when no data_repo specified" do
      query = %Query{
        name: "Default Repo Query",
        statement: "SELECT 1 as result",
        variables: []
      }

      assert {:ok, result} = Lotus.run_query(query)
      assert result.num_rows == 1
      assert result.rows == [[1]]
    end
  end

  describe "run_query/2 with query ID" do
    test "gets query by ID and runs it" do
      query =
        query_fixture(%{
          name: "ID Query",
          statement: "SELECT name FROM test_users WHERE active = false"
        })

      assert {:ok, result} = Lotus.run_query(query.id)
      assert result.num_rows == 1
      assert result.rows == [["Charles Bukowski"]]
    end

    test "passes options through" do
      query =
        query_fixture(%{
          name: "ID with Options Query",
          statement: "SELECT 1 as result"
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

  describe "can_run?/2" do
    alias Lotus.Storage.{Query, QueryVariable}

    test "returns true for query with no variables" do
      query = %Query{
        name: "No Vars Query",
        statement: "SELECT name FROM test_users WHERE active = true",
        variables: []
      }

      assert Lotus.can_run?(query) == true
    end

    test "returns true for query with variables that have defaults" do
      query = %Query{
        name: "Query with Defaults",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "30"}
        ]
      }

      assert Lotus.can_run?(query) == true
    end

    test "returns false for query with required variables and no defaults" do
      query = %Query{
        name: "Query with Required Vars",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number}
        ]
      }

      assert Lotus.can_run?(query) == false
    end

    test "returns true when runtime vars fill missing required variables" do
      query = %Query{
        name: "Query with Runtime Vars",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}} AND name = {{name}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "30"},
          %QueryVariable{name: "name", type: :text}
        ]
      }

      assert Lotus.can_run?(query) == false
      assert Lotus.can_run?(query, vars: %{"name" => "Jack Kerouac"}) == true
    end

    test "returns false when some required variables are still missing" do
      query = %Query{
        name: "Query with Multiple Required Vars",
        statement:
          "SELECT name FROM test_users WHERE age > {{min_age}} AND name = {{name}} AND active = {{is_active}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number},
          %QueryVariable{name: "name", type: :text},
          %QueryVariable{name: "is_active", type: :text}
        ]
      }

      # No variables provided
      assert Lotus.can_run?(query) == false

      # Only some variables provided
      assert Lotus.can_run?(query, vars: %{"min_age" => 30}) == false
      assert Lotus.can_run?(query, vars: %{"min_age" => 30, "name" => "Jack"}) == false

      # All variables provided
      assert Lotus.can_run?(query,
               vars: %{"min_age" => 30, "name" => "Jack", "is_active" => "true"}
             ) == true
    end

    test "returns true when runtime vars override defaults" do
      query = %Query{
        name: "Query with Overrides",
        statement: "SELECT name FROM test_users WHERE age > {{min_age}}",
        variables: [
          %QueryVariable{name: "min_age", type: :number, default: "30"}
        ]
      }

      assert Lotus.can_run?(query) == true
      assert Lotus.can_run?(query, vars: %{"min_age" => 50}) == true
    end
  end

  describe "configuration delegates" do
    test "unique_names?/0 delegates to Config.unique_names?/0" do
      assert Lotus.unique_names?() == Config.unique_names?()
    end
  end
end
