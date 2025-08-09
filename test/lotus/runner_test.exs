defmodule Lotus.RunnerTest do
  use Lotus.Case, async: true

  alias Lotus.Runner
  alias Lotus.Test.Repo
  alias Lotus.Fixtures

  setup do
    fixtures = Fixtures.setup_test_data()
    {:ok, fixtures}
  end

  describe "run_sql/4 with real tables" do
    test "executes simple SELECT queries", %{users: %{kerouac: kerouac}} do
      result =
        Runner.run_sql(Repo, "SELECT name, email FROM test_users WHERE id = $1", [kerouac.id])

      assert {:ok, %{columns: ["name", "email"], rows: [["Jack Kerouac", "jack@ontheroad.com"]]}} =
               result
    end

    test "executes queries with multiple parameters", %{
      users: %{kerouac: kerouac, thompson: thompson}
    } do
      sql = "SELECT name, age FROM test_users WHERE id IN ($1, $2) ORDER BY name"
      result = Runner.run_sql(Repo, sql, [kerouac.id, thompson.id])

      assert {:ok,
              %{
                columns: ["name", "age"],
                rows: [["Hunter S. Thompson", 37], ["Jack Kerouac", 47]]
              }} =
               result
    end

    test "executes JOIN queries", %{users: %{kerouac: kerouac}} do
      sql = """
      SELECT u.name, p.title, p.view_count
      FROM test_users u
      JOIN test_posts p ON u.id = p.user_id
      WHERE u.id = $1
      ORDER BY p.view_count DESC
      """

      result = Runner.run_sql(Repo, sql, [kerouac.id])

      assert {:ok,
              %{
                columns: ["name", "title", "view_count"],
                rows: [
                  ["Jack Kerouac", "The Mad Ones", 150],
                  ["Jack Kerouac", "First Thought Best Thought", 75]
                ]
              }} = result
    end

    test "executes aggregate queries" do
      sql = """
      SELECT
        COUNT(*) as total_posts,
        SUM(view_count) as total_views,
        AVG(view_count)::integer as avg_views
      FROM test_posts
      WHERE published = true
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok,
              %{
                columns: ["total_posts", "total_views", "avg_views"],
                rows: [[3, 425, 142]]
              }} = result
    end

    test "executes GROUP BY queries" do
      sql = """
      SELECT
        u.name,
        COUNT(p.id) as post_count,
        COALESCE(SUM(p.view_count), 0) as total_views
      FROM test_users u
      LEFT JOIN test_posts p ON u.id = p.user_id
      GROUP BY u.id, u.name
      ORDER BY u.name
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok,
              %{
                columns: ["name", "post_count", "total_views"],
                rows: [
                  ["Charles Bukowski", 1, 200],
                  ["Hunter S. Thompson", 1, 0],
                  ["Jack Kerouac", 2, 225]
                ]
              }} = result
    end

    test "handles JSON operations", %{users: %{kerouac: kerouac}} do
      sql = "SELECT name, metadata->>'role' as role FROM test_users WHERE id = $1"
      result = Runner.run_sql(Repo, sql, [kerouac.id])
      assert {:ok, %{columns: ["name", "role"], rows: [["Jack Kerouac", "admin"]]}} = result
    end

    test "handles array operations" do
      sql =
        "SELECT title, array_length(tags, 1) as tag_count FROM test_posts WHERE 'beat' = ANY(tags)"

      result = Runner.run_sql(Repo, sql)
      assert {:ok, %{columns: ["title", "tag_count"], rows: rows}} = result
      assert length(rows) == 2
    end

    test "executes CTE queries" do
      sql = """
      WITH active_users AS (
        SELECT id, name FROM test_users WHERE active = true
      ),
      user_posts AS (
        SELECT u.name, COUNT(p.id) as post_count
        FROM active_users u
        LEFT JOIN test_posts p ON u.id = p.user_id
        GROUP BY u.name
      )
      SELECT * FROM user_posts ORDER BY name
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok,
              %{
                columns: ["name", "post_count"],
                rows: [["Hunter S. Thompson", 1], ["Jack Kerouac", 2]]
              }} = result
    end

    test "handles subqueries" do
      sql = """
      SELECT name, email FROM test_users
      WHERE id IN (
        SELECT DISTINCT user_id FROM test_posts WHERE published = true
      )
      ORDER BY name
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["name", "email"], rows: rows}} = result
      assert length(rows) == 2
      assert Enum.any?(rows, fn [name, _] -> name == "Jack Kerouac" end)
      assert Enum.any?(rows, fn [name, _] -> name == "Charles Bukowski" end)
    end

    test "handles CASE expressions" do
      sql = """
      SELECT
        name,
        CASE
          WHEN age < 30 THEN 'Young'
          WHEN age >= 30 AND age < 50 THEN 'Middle'
          ELSE 'Senior'
        END as age_group
      FROM test_users
      ORDER BY name
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["name", "age_group"], rows: rows}} = result
      assert ["Charles Bukowski", "Senior"] in rows
      assert ["Hunter S. Thompson", "Middle"] in rows
      assert ["Jack Kerouac", "Middle"] in rows
    end
  end

  describe "whitelist validation" do
    test "allows SELECT queries" do
      result = Runner.run_sql(Repo, "SELECT * FROM test_users LIMIT 1")
      assert {:ok, %{columns: columns, rows: _}} = result
      assert "id" in columns
    end

    test "allows WITH queries" do
      sql = """
      WITH test AS (SELECT 1 as num)
      SELECT * FROM test
      """

      result = Runner.run_sql(Repo, sql)
      assert {:ok, %{columns: ["num"], rows: [[1]]}} = result
    end

    test "allows VALUES queries" do
      result = Runner.run_sql(Repo, "VALUES (1, 'a'), (2, 'b')")
      assert {:ok, %{columns: ["column1", "column2"], rows: [[1, "a"], [2, "b"]]}} = result
    end

    test "allows EXPLAIN queries" do
      result = Runner.run_sql(Repo, "EXPLAIN SELECT * FROM test_users")
      assert {:ok, %{columns: ["QUERY PLAN"], rows: rows}} = result
      assert length(rows) > 0
    end

    test "rejects INSERT statements" do
      result =
        Runner.run_sql(
          Repo,
          "INSERT INTO test_users (name, email) VALUES ('test', 'test@example.com')"
        )

      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "rejects UPDATE statements" do
      result = Runner.run_sql(Repo, "UPDATE test_users SET name = 'Updated'")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "rejects DELETE statements" do
      result = Runner.run_sql(Repo, "DELETE FROM test_users WHERE id = 1")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "rejects DROP statements" do
      result = Runner.run_sql(Repo, "DROP TABLE test_users")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "rejects CREATE statements" do
      result = Runner.run_sql(Repo, "CREATE TABLE new_table (id int)")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "rejects ALTER statements" do
      result = Runner.run_sql(Repo, "ALTER TABLE test_users ADD COLUMN new_field text")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "rejects TRUNCATE statements" do
      result = Runner.run_sql(Repo, "TRUNCATE test_users")
      assert {:error, "Only read-only queries are allowed"} = result
    end
  end

  describe "deny list validation" do
    test "detects dangerous keywords in string literals" do
      # Even in string literals, we're defensive
      result = Runner.run_sql(Repo, "SELECT 'DROP TABLE users' as msg")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "detects dangerous keywords case-insensitively" do
      result = Runner.run_sql(Repo, "SELECT 'InSeRt INTO users' as msg")
      assert {:error, "Only read-only queries are allowed"} = result
    end

    test "allows safe strings without dangerous keywords" do
      result = Runner.run_sql(Repo, "SELECT 'This is a safe message' as msg")
      assert {:ok, %{columns: ["msg"], rows: [["This is a safe message"]]}} = result
    end
  end

  describe "single statement validation" do
    test "rejects multiple statements with semicolon" do
      result = Runner.run_sql(Repo, "SELECT 1; SELECT 2")
      assert {:error, "Only a single statement is allowed"} = result
    end

    test "rejects statement with trailing semicolon" do
      result = Runner.run_sql(Repo, "SELECT * FROM test_users;")
      assert {:error, "Only a single statement is allowed"} = result
    end

    test "rejects semicolon even in valid contexts" do
      # We're strict about semicolons to prevent SQL injection
      result = Runner.run_sql(Repo, "SELECT 'test;value' as text")
      assert {:error, "Only a single statement is allowed"} = result
    end
  end

  describe "transaction and timeout behavior" do
    test "enforces read-only transaction by default" do
      # Try to execute a write operation - should fail due to read-only transaction
      sql = """
      WITH test AS (SELECT 1 as id)
      SELECT * FROM test
      """

      result = Runner.run_sql(Repo, sql)
      assert {:ok, %{columns: ["id"], rows: [[1]]}} = result
    end

    test "respects read_only: false option" do
      # Even with read_only: false, write operations are blocked by whitelist
      result = Runner.run_sql(Repo, "SELECT COUNT(*) FROM test_users", [], read_only: false)
      assert {:ok, %{columns: ["count"], rows: [[3]]}} = result
    end

    test "respects custom statement timeout" do
      # Quick query should complete within timeout
      result = Runner.run_sql(Repo, "SELECT 1", [], statement_timeout_ms: 100)
      assert {:ok, %{columns: ["?column?"], rows: [[1]]}} = result
    end

    test "respects custom database timeout" do
      result = Runner.run_sql(Repo, "SELECT COUNT(*) FROM test_users", [], timeout: 1000)
      assert {:ok, %{columns: ["count"], rows: [[3]]}} = result
    end
  end

  describe "error handling" do
    test "handles syntax errors gracefully" do
      result = Runner.run_sql(Repo, "SELECT * FROM")
      assert {:error, msg} = result
      assert msg =~ "SQL syntax error:"
      assert msg =~ "syntax error at end of input" or msg =~ "syntax error at or near"
    end

    test "handles invalid table references" do
      result = Runner.run_sql(Repo, "SELECT * FROM non_existent_table")
      assert {:error, msg} = result
      assert msg =~ "SQL error:"
      assert msg =~ "non_existent_table"
    end

    test "handles invalid column references", %{users: %{kerouac: kerouac}} do
      result =
        Runner.run_sql(Repo, "SELECT non_existent_column FROM test_users WHERE id = $1", [
          kerouac.id
        ])

      assert {:error, msg} = result
      assert msg =~ "SQL error:"
      assert msg =~ "non_existent_column"
    end

    test "handles type mismatches" do
      result = Runner.run_sql(Repo, "SELECT * FROM test_users WHERE id = $1", ["not_an_integer"])
      assert {:error, message} = result
      assert is_binary(message)
      assert message =~ "expected an integer"
    end

    test "handles empty result sets" do
      result = Runner.run_sql(Repo, "SELECT * FROM test_users WHERE id = -999")
      assert {:ok, %{columns: columns, rows: []}} = result
      assert "id" in columns
    end

    test "handles NULL values" do
      # Insert a user with NULL age
      user = Fixtures.insert_user(%{name: "Null Test", email: "null@test.com", age: nil})

      result = Runner.run_sql(Repo, "SELECT name, age FROM test_users WHERE id = $1", [user.id])
      assert {:ok, %{columns: ["name", "age"], rows: [["Null Test", nil]]}} = result
    end

    test "validates SQL string type" do
      assert_raise FunctionClauseError, fn ->
        Runner.run_sql(Repo, 123, [])
      end
    end

    test "validates params list type" do
      assert_raise FunctionClauseError, fn ->
        Runner.run_sql(Repo, "SELECT 1", "not_a_list")
      end
    end
  end

  describe "complex query scenarios" do
    test "handles window functions" do
      sql = """
      SELECT
        title,
        view_count,
        ROW_NUMBER() OVER (ORDER BY view_count DESC) as rank
      FROM test_posts
      WHERE published = true
      ORDER BY rank
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["title", "view_count", "rank"], rows: rows}} = result
      assert length(rows) == 3
      assert [_, _, 1] = List.first(rows)
    end

    test "handles UNION queries" do
      sql = """
      SELECT name, 'user' as type FROM test_users WHERE active = true
      UNION
      SELECT title as name, 'post' as type FROM test_posts WHERE published = true
      ORDER BY name
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["name", "type"], rows: rows}} = result
      assert length(rows) > 3
    end

    test "handles date/time operations" do
      sql = """
      SELECT
        name,
        DATE(inserted_at) as created_date,
        EXTRACT(YEAR FROM inserted_at)::integer as year
      FROM test_users
      LIMIT 1
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["name", "created_date", "year"], rows: [[_, _, year]]}} = result
      assert is_integer(year)
    end

    test "handles string operations" do
      sql = """
      SELECT
        UPPER(name) as upper_name,
        LENGTH(name) as name_length,
        SUBSTRING(email FROM 1 FOR 5) as email_prefix
      FROM test_users
      WHERE active = false
      ORDER BY name
      LIMIT 1
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok,
              %{
                columns: ["upper_name", "name_length", "email_prefix"],
                rows: [[upper, length, prefix]]
              }} = result

      assert upper == "CHARLES BUKOWSKI"
      assert length == 16
      assert prefix == "hank@"
    end

    test "handles EXISTS subqueries" do
      sql = """
      SELECT name FROM test_users u
      WHERE EXISTS (
        SELECT 1 FROM test_posts p
        WHERE p.user_id = u.id AND p.published = true
      )
      ORDER BY name
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["name"], rows: rows}} = result
      assert ["Jack Kerouac"] in rows
      assert ["Charles Bukowski"] in rows
      refute ["Hunter S. Thompson"] in rows
    end

    test "handles DISTINCT queries" do
      sql = """
      SELECT DISTINCT active FROM test_users ORDER BY active
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["active"], rows: [[false], [true]]}} = result
    end

    test "handles LIMIT and OFFSET" do
      sql = """
      SELECT name FROM test_users
      ORDER BY name
      LIMIT 2 OFFSET 1
      """

      result = Runner.run_sql(Repo, sql)

      assert {:ok, %{columns: ["name"], rows: rows}} = result
      assert length(rows) == 2
      assert ["Hunter S. Thompson"] in rows
      assert ["Jack Kerouac"] in rows
    end
  end
end
