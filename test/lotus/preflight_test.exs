defmodule Lotus.PreflightTest do
  use Lotus.Case
  alias Lotus.Preflight

  @pg_repo Lotus.Test.Repo
  @sqlite_repo Lotus.Test.SqliteRepo

  describe "PostgreSQL preflight authorization" do
    test "allows queries against regular tables" do
      assert :ok = Preflight.authorize(@pg_repo, "postgres", "SELECT 1", [])

      assert :ok =
               Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM test_users LIMIT 1", [])
    end

    test "allows complex queries with JOINs" do
      sql = """
        SELECT u.name, p.title, p.content
        FROM test_users u
        JOIN test_posts p ON u.id = p.user_id
        WHERE u.active = true
        LIMIT 10
      """

      assert :ok = Preflight.authorize(@pg_repo, "postgres", sql, [])
    end

    test "allows simple queries" do
      assert :ok =
               Preflight.authorize(
                 @pg_repo,
                 "postgres",
                 "SELECT * FROM test_posts WHERE published = true",
                 []
               )

      assert :ok =
               Preflight.authorize(@pg_repo, "postgres", "SELECT COUNT(*) FROM test_users", [])
    end

    test "allows subqueries and CTEs" do
      # Subquery
      sql = """
        SELECT * FROM test_users 
        WHERE id IN (SELECT user_id FROM test_posts WHERE published = true)
      """

      assert :ok = Preflight.authorize(@pg_repo, "postgres", sql, [])

      # CTE
      sql = """
        WITH user_stats AS (
          SELECT u.id, u.name, COUNT(p.id) as post_count
          FROM test_users u
          LEFT JOIN test_posts p ON u.id = p.user_id
          GROUP BY u.id, u.name
        )
        SELECT * FROM user_stats WHERE post_count > 0
      """

      assert :ok = Preflight.authorize(@pg_repo, "postgres", sql, [])
    end

    test "blocks queries against pg_catalog" do
      {:error, msg} =
        Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM pg_catalog.pg_tables", [])

      assert msg =~ "blocked table"
      assert msg =~ "pg_catalog"
    end

    test "blocks queries against information_schema" do
      {:error, msg} =
        Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM information_schema.tables", [])

      assert msg =~ "blocked table"
      # information_schema queries actually touch pg_catalog tables internally
      assert msg =~ "pg_catalog"
    end

    test "blocks queries against framework tables" do
      {:error, msg} = Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM lotus_queries", [])
      assert msg =~ "blocked table"
      assert msg =~ "lotus_queries"
    end

    test "blocks JOINs that include denied tables" do
      sql = """
        SELECT u.name, lq.name
        FROM test_users u
        JOIN lotus_queries lq ON true
      """

      {:error, msg} = Preflight.authorize(@pg_repo, "postgres", sql, [])
      assert msg =~ "blocked table"
      assert msg =~ "lotus_queries"
    end

    test "handles parameterized queries" do
      assert :ok =
               Preflight.authorize(
                 @pg_repo,
                 "postgres",
                 "SELECT * FROM test_users WHERE id = $1",
                 [1]
               )

      assert :ok =
               Preflight.authorize(
                 @pg_repo,
                 "postgres",
                 "SELECT * FROM test_posts WHERE view_count > $1",
                 [10]
               )
    end

    test "handles syntax errors gracefully" do
      {:error, _msg} = Preflight.authorize(@pg_repo, "postgres", "INVALID SQL SYNTAX", [])
    end
  end

  describe "SQLite preflight authorization" do
    @tag :sqlite
    test "allows queries against regular tables" do
      assert :ok = Preflight.authorize(@sqlite_repo, "sqlite", "SELECT 1", [])

      assert :ok =
               Preflight.authorize(@sqlite_repo, "sqlite", "SELECT * FROM products LIMIT 1", [])
    end

    @tag :sqlite
    test "allows complex queries with JOINs" do
      sql = """
        SELECT p.name, o.order_number, o.total_amount
        FROM products p
        JOIN order_items oi ON p.id = oi.product_id
        JOIN orders o ON oi.order_id = o.id
        WHERE p.active = 1
        LIMIT 10
      """

      assert :ok = Preflight.authorize(@sqlite_repo, "sqlite", sql, [])
    end

    @tag :sqlite
    test "allows simple queries" do
      assert :ok =
               Preflight.authorize(
                 @sqlite_repo,
                 "sqlite",
                 "SELECT * FROM orders WHERE status = 'pending'",
                 []
               )

      assert :ok =
               Preflight.authorize(@sqlite_repo, "sqlite", "SELECT COUNT(*) FROM products", [])
    end

    @tag :sqlite
    test "allows subqueries and CTEs" do
      # Subquery
      sql = """
        SELECT * FROM products 
        WHERE id IN (SELECT product_id FROM order_items WHERE quantity > 1)
      """

      assert :ok = Preflight.authorize(@sqlite_repo, "sqlite", sql, [])

      # CTE
      sql = """
        WITH product_stats AS (
          SELECT p.id, p.name, COUNT(oi.id) as order_count
          FROM products p
          LEFT JOIN order_items oi ON p.id = oi.product_id
          GROUP BY p.id, p.name
        )
        SELECT * FROM product_stats WHERE order_count > 0
      """

      assert :ok = Preflight.authorize(@sqlite_repo, "sqlite", sql, [])
    end

    @tag :sqlite
    test "blocks queries against system tables" do
      {:error, msg} =
        Preflight.authorize(@sqlite_repo, "sqlite", "SELECT * FROM sqlite_master", [])

      assert msg =~ "blocked table"
      assert msg =~ "sqlite_master"
    end

    @tag :sqlite
    test "blocks queries against framework tables" do
      {:error, msg} =
        Preflight.authorize(
          @sqlite_repo,
          "sqlite",
          "SELECT * FROM lotus_sqlite_schema_migrations",
          []
        )

      assert msg =~ "blocked table"
      assert msg =~ "schema_migrations"
    end

    @tag :sqlite
    test "blocks JOINs that include denied tables" do
      sql = """
        SELECT p.name, sm.version
        FROM products p
        JOIN lotus_sqlite_schema_migrations sm ON 1=1
      """

      {:error, msg} = Preflight.authorize(@sqlite_repo, "sqlite", sql, [])
      assert msg =~ "blocked table"
      assert msg =~ "schema_migrations"
    end

    @tag :sqlite
    test "handles parameterized queries" do
      assert :ok =
               Preflight.authorize(
                 @sqlite_repo,
                 "sqlite",
                 "SELECT * FROM products WHERE id = ?",
                 [1]
               )

      assert :ok =
               Preflight.authorize(
                 @sqlite_repo,
                 "sqlite",
                 "SELECT * FROM orders WHERE total_amount > ?",
                 [10.0]
               )
    end

    @tag :sqlite
    test "handles syntax errors gracefully" do
      {:error, _msg} = Preflight.authorize(@sqlite_repo, "sqlite", "INVALID SQL SYNTAX", [])
    end
  end

  describe "error handling" do
    test "handles invalid repo gracefully" do
      assert {:error, msg} = Preflight.authorize(@pg_repo, "unknown_repo", "SELECT 1", [])
      assert msg == "Unknown data repo 'unknown_repo'"
    end
  end
end
