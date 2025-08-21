defmodule Lotus.VisibilityTest do
  use ExUnit.Case
  use Mimic

  alias Lotus.Visibility

  setup do
    Mimic.copy(Lotus.Config)
    :ok
  end

  describe "built-in deny rules" do
    test "denies PostgreSQL system catalogs" do
      refute Visibility.allowed_relation?("postgres", {"pg_catalog", "pg_class"})
      refute Visibility.allowed_relation?("postgres", {"pg_catalog", "pg_tables"})

      refute Visibility.allowed_relation?("postgres", {"information_schema", "tables"})
      refute Visibility.allowed_relation?("postgres", {"information_schema", "columns"})
    end

    test "denies framework metadata tables in PostgreSQL" do
      refute Visibility.allowed_relation?("postgres", {"public", "schema_migrations"})
      refute Visibility.allowed_relation?("postgres", {"public", "lotus_queries"})
    end

    test "denies framework metadata tables in SQLite" do
      refute Visibility.allowed_relation?("sqlite", {nil, "lotus_sqlite_schema_migrations"})
      refute Visibility.allowed_relation?("sqlite", {nil, "lotus_queries"})
    end

    test "denies SQLite system tables" do
      refute Visibility.allowed_relation?("sqlite", {nil, "sqlite_master"})
      refute Visibility.allowed_relation?("sqlite", {nil, "sqlite_sequence"})
      refute Visibility.allowed_relation?("sqlite", {nil, "sqlite_stat1"})
    end

    test "allows regular business tables" do
      assert Visibility.allowed_relation?("postgres", {"public", "users"})
      assert Visibility.allowed_relation?("postgres", {"public", "orders"})
      assert Visibility.allowed_relation?("sqlite", {nil, "products"})
      assert Visibility.allowed_relation?("sqlite", {nil, "customers"})
    end
  end

  describe "user-configured allow rules" do
    setup do
      allow_config = [
        allow: [
          {"public", "users"},
          {"public", "orders"},
          # SQLite
          {nil, "products"}
        ],
        deny: []
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> allow_config end)
      :ok
    end

    test "only allows explicitly listed tables when allow rules are present" do
      assert Visibility.allowed_relation?("postgres", {"public", "users"})
      assert Visibility.allowed_relation?("postgres", {"public", "orders"})
      assert Visibility.allowed_relation?("sqlite", {nil, "products"})

      refute Visibility.allowed_relation?("postgres", {"public", "posts"})
      refute Visibility.allowed_relation?("sqlite", {nil, "categories"})

      refute Visibility.allowed_relation?("postgres", {"public", "schema_migrations"})
    end
  end

  describe "user-configured deny rules" do
    setup do
      deny_config = [
        allow: [],
        deny: [
          {"public", "sensitive_data"},
          {"public", ~r/^temp_/},
          {nil, "private_table"}
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> deny_config end)
      :ok
    end

    test "denies explicitly listed tables" do
      refute Visibility.allowed_relation?("postgres", {"public", "sensitive_data"})
      refute Visibility.allowed_relation?("sqlite", {nil, "private_table"})
    end

    test "denies tables matching regex patterns" do
      refute Visibility.allowed_relation?("postgres", {"public", "temp_users"})
      refute Visibility.allowed_relation?("postgres", {"public", "temp_cache"})
      refute Visibility.allowed_relation?("postgres", {"public", "temp_whatever"})
    end

    test "allows tables not in deny list" do
      assert Visibility.allowed_relation?("postgres", {"public", "users"})
      assert Visibility.allowed_relation?("postgres", {"public", "orders"})
      assert Visibility.allowed_relation?("sqlite", {nil, "products"})
    end

    test "built-in denied tables are still denied" do
      refute Visibility.allowed_relation?("postgres", {"public", "schema_migrations"})
      refute Visibility.allowed_relation?("sqlite", {nil, "sqlite_master"})
    end
  end

  describe "regex pattern matching" do
    setup do
      regex_config = [
        allow: [],
        deny: [
          {"public", ~r/^internal_/},
          {nil, ~r/_backup$/},
          # deny entire schema
          {"analytics", ~r/.*/}
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> regex_config end)
      :ok
    end

    test "matches prefix patterns" do
      refute Visibility.allowed_relation?("postgres", {"public", "internal_users"})
      refute Visibility.allowed_relation?("postgres", {"public", "internal_logs"})
      refute Visibility.allowed_relation?("postgres", {"public", "internal_anything"})
    end

    test "matches suffix patterns" do
      refute Visibility.allowed_relation?("sqlite", {nil, "users_backup"})
      refute Visibility.allowed_relation?("sqlite", {nil, "orders_backup"})
      refute Visibility.allowed_relation?("sqlite", {nil, "anything_backup"})
    end

    test "matches entire schema patterns" do
      refute Visibility.allowed_relation?("postgres", {"analytics", "users"})
      refute Visibility.allowed_relation?("postgres", {"analytics", "anything"})
    end

    test "allows tables not matching patterns" do
      assert Visibility.allowed_relation?("postgres", {"public", "users"})
      assert Visibility.allowed_relation?("postgres", {"public", "prefix_internal"})
      assert Visibility.allowed_relation?("sqlite", {nil, "backup_suffix"})
    end
  end

  describe "SQLite convenience syntax" do
    setup do
      sqlite_config = [
        allow: [],
        deny: [
          "temp_table",
          "another_temp"
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> sqlite_config end)
      :ok
    end

    test "matches bare table names for SQLite" do
      refute Visibility.allowed_relation?("sqlite", {nil, "temp_table"})
      refute Visibility.allowed_relation?("sqlite", {"", "temp_table"})
      refute Visibility.allowed_relation?("sqlite", {nil, "another_temp"})
    end

    test "does not match bare table names for PostgreSQL with schema" do
      assert Visibility.allowed_relation?("postgres", {"public", "temp_table"})
    end
  end

  describe "edge cases" do
    setup do
      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> [] end)
      :ok
    end

    test "handles empty configuration gracefully" do
      assert Visibility.allowed_relation?("postgres", {"public", "users"})
      assert Visibility.allowed_relation?("sqlite", {nil, "products"})

      refute Visibility.allowed_relation?("postgres", {"public", "schema_migrations"})
      refute Visibility.allowed_relation?("sqlite", {nil, "sqlite_master"})
    end

    test "handles nil schemas properly" do
      assert Visibility.allowed_relation?("sqlite", {nil, "regular_table"})
      refute Visibility.allowed_relation?("sqlite", {nil, "lotus_sqlite_schema_migrations"})
    end

    test "handles empty string schemas" do
      assert Visibility.allowed_relation?("sqlite", {"", "regular_table"})
    end
  end

  describe "rule precedence" do
    test "deny rules take precedence over allow rules" do
      precedence_config = [
        allow: [
          {"public", "special_table"}
        ],
        deny: [
          {"public", "special_table"}
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> precedence_config end)

      refute Visibility.allowed_relation?("postgres", {"public", "special_table"})
    end

    test "built-in deny rules always take precedence" do
      precedence_config = [
        allow: [
          {"public", "schema_migrations"}
        ],
        deny: []
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> precedence_config end)

      refute Visibility.allowed_relation?("postgres", {"public", "schema_migrations"})
    end
  end

  describe "realistic BI scenarios" do
    test "typical data warehouse setup" do
      warehouse_config = [
        allow: [
          {"public", ~r/^dim_/},
          {"public", ~r/^fact_/},
          {"analytics", ~r/.*/}
        ],
        deny: [
          {"public", ~r/^staging_/},
          {"public", ~r/_temp$/}
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> warehouse_config end)

      assert Visibility.allowed_relation?("postgres", {"public", "dim_customers"})
      assert Visibility.allowed_relation?("postgres", {"public", "fact_sales"})

      assert Visibility.allowed_relation?("postgres", {"analytics", "customer_metrics"})

      refute Visibility.allowed_relation?("postgres", {"public", "staging_users"})
      refute Visibility.allowed_relation?("postgres", {"public", "import_temp"})

      refute Visibility.allowed_relation?("postgres", {"public", "random_table"})

      refute Visibility.allowed_relation?("postgres", {"public", "schema_migrations"})
    end

    test "simple business database" do
      business_config = [
        allow: [],
        deny: [
          {"public", "user_passwords"},
          {"public", ~r/^audit_/},
          {"public", ~r/_log$/}
        ]
      ]

      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> business_config end)

      assert Visibility.allowed_relation?("postgres", {"public", "users"})
      assert Visibility.allowed_relation?("postgres", {"public", "orders"})
      assert Visibility.allowed_relation?("postgres", {"public", "products"})

      refute Visibility.allowed_relation?("postgres", {"public", "user_passwords"})
      refute Visibility.allowed_relation?("postgres", {"public", "audit_trail"})
      refute Visibility.allowed_relation?("postgres", {"public", "access_log"})
    end
  end
end
