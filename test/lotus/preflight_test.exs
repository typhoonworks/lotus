defmodule Lotus.PreflightTest do
  use Lotus.Case
  use Mimic
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

  describe "PostgreSQL preflight with bare string deny rules" do
    setup do
      Mimic.copy(Lotus.Config)

      config = [
        allow: [],
        deny: [
          "test_posts",
          "test_comments"
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> config end)
      :ok
    end

    test "blocks queries against tables matching bare string deny rules in public schema" do
      {:error, msg} = Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM test_posts", [])
      assert msg =~ "blocked table"
      assert msg =~ "test_posts"
    end

    test "blocks queries against tables matching bare string deny rules with explicit schema" do
      {:error, msg} =
        Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM public.test_posts", [])

      assert msg =~ "blocked table"
      assert msg =~ "test_posts"
    end

    test "blocks JOIN queries including denied tables" do
      sql = """
        SELECT u.name, p.title
        FROM test_users u
        JOIN test_posts p ON u.id = p.user_id
      """

      {:error, msg} = Preflight.authorize(@pg_repo, "postgres", sql, [])
      assert msg =~ "blocked table"
      assert msg =~ "test_posts"
    end

    test "allows queries against tables not in deny list" do
      assert :ok = Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM test_users", [])
      assert :ok = Preflight.authorize(@pg_repo, "postgres", "SELECT 1", [])
    end
  end

  describe "PostgreSQL preflight with bare string allow rules" do
    setup do
      Mimic.copy(Lotus.Config)

      config = [
        allow: [
          "test_users"
        ],
        deny: []
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> config end)
      :ok
    end

    test "allows queries against tables matching bare string allow rules" do
      assert :ok = Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM test_users", [])
    end

    test "allows queries with explicit schema for allowed tables" do
      assert :ok =
               Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM public.test_users", [])
    end

    test "blocks queries against tables not in allow list" do
      {:error, msg} = Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM test_posts", [])
      assert msg =~ "blocked table"
      assert msg =~ "test_posts"
    end
  end

  describe "PostgreSQL preflight with mixed rule formats" do
    setup do
      Mimic.copy(Lotus.Config)

      config = [
        allow: [],
        deny: [
          "test_comments",
          {"public", "test_posts"}
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> config end)
      :ok
    end

    test "tuple with schema only blocks in that specific schema" do
      {:error, msg} =
        Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM public.test_posts", [])

      assert msg =~ "blocked table"
      assert msg =~ "test_posts"
    end

    test "allows tables not matching any deny rules" do
      assert :ok = Preflight.authorize(@pg_repo, "postgres", "SELECT * FROM test_users", [])
    end
  end

  describe "SQLite preflight with bare string deny rules" do
    setup do
      Mimic.copy(Lotus.Config)

      config = [
        allow: [],
        deny: [
          "products",
          "order_items"
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> config end)
      :ok
    end

    @tag :sqlite
    test "blocks queries against tables matching bare string deny rules" do
      {:error, msg} = Preflight.authorize(@sqlite_repo, "sqlite", "SELECT * FROM products", [])
      assert msg =~ "blocked table"
      assert msg =~ "products"

      {:error, msg} = Preflight.authorize(@sqlite_repo, "sqlite", "SELECT * FROM order_items", [])
      assert msg =~ "blocked table"
      assert msg =~ "order_items"
    end

    @tag :sqlite
    test "blocks JOIN queries including denied tables" do
      sql = """
        SELECT o.order_number, p.name
        FROM orders o
        JOIN order_items oi ON o.id = oi.order_id
        JOIN products p ON oi.product_id = p.id
      """

      {:error, msg} = Preflight.authorize(@sqlite_repo, "sqlite", sql, [])
      assert msg =~ "blocked table"
      assert msg =~ "products"
      assert msg =~ "order_items"
    end

    @tag :sqlite
    test "allows queries against tables not in deny list" do
      assert :ok = Preflight.authorize(@sqlite_repo, "sqlite", "SELECT * FROM orders", [])
    end
  end
end
