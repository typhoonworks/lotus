defmodule Lotus.Storage.VariableResolverTest do
  use Lotus.Case, async: true

  alias Lotus.Storage.VariableResolver

  describe "resolve_variables/1 with explicit bindings" do
    test "extracts table.column = {{var}} pattern" do
      sql = "SELECT * FROM users WHERE users.id = {{user_id}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "user_id", table: "users", column: "id"}] = result
    end

    test "extracts multiple explicit bindings" do
      sql = """
      SELECT * FROM users
      WHERE users.id = {{id}}
        AND users.email = {{email}}
        AND users.status = {{status}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert length(result) == 3

      assert Enum.any?(
               result,
               &(&1.variable == "id" and &1.table == "users" and &1.column == "id")
             )

      assert Enum.any?(
               result,
               &(&1.variable == "email" and &1.table == "users" and &1.column == "email")
             )

      assert Enum.any?(
               result,
               &(&1.variable == "status" and &1.table == "users" and &1.column == "status")
             )
    end

    test "handles different table for each binding" do
      sql = """
      SELECT * FROM users u
      JOIN orders o ON o.user_id = u.id
      WHERE users.id = {{user_id}}
        AND orders.total = {{order_total}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert Enum.any?(result, &(&1.variable == "user_id" and &1.table == "users"))
      assert Enum.any?(result, &(&1.variable == "order_total" and &1.table == "orders"))
    end
  end

  describe "resolve_variables/1 with table aliases" do
    test "resolves simple alias from FROM clause" do
      sql = "SELECT * FROM users u WHERE u.id = {{user_id}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "user_id", table: "users", column: "id"}] = result
    end

    test "resolves alias with AS keyword" do
      sql = "SELECT * FROM users AS u WHERE u.id = {{user_id}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "user_id", table: "users", column: "id"}] = result
    end

    test "resolves JOIN alias" do
      sql = """
      SELECT * FROM users u
      JOIN orders o ON o.user_id = u.id
      WHERE o.total = {{order_total}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert Enum.any?(result, &(&1.variable == "order_total" and &1.table == "orders"))
    end

    test "resolves multiple JOIN aliases" do
      sql = """
      SELECT * FROM users u
      JOIN orders o ON o.user_id = u.id
      JOIN products p ON p.id = o.product_id
      WHERE u.status = {{user_status}}
        AND o.total = {{order_total}}
        AND p.price = {{product_price}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert Enum.any?(result, &(&1.variable == "user_status" and &1.table == "users"))
      assert Enum.any?(result, &(&1.variable == "order_total" and &1.table == "orders"))
      assert Enum.any?(result, &(&1.variable == "product_price" and &1.table == "products"))
    end
  end

  describe "resolve_variables/1 with implicit bindings" do
    test "infers table from FROM clause" do
      sql = "SELECT * FROM users WHERE id = {{user_id}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "user_id", table: "users", column: "id"}] = result
    end

    test "infers table for multiple implicit variables" do
      sql = """
      SELECT * FROM orders
      WHERE status = {{status}} AND total > {{min_total}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert length(result) == 2
      assert Enum.all?(result, &(&1.table == "orders"))
    end

    test "uses first table from FROM clause" do
      sql = """
      SELECT * FROM users, orders
      WHERE id = {{user_id}}
      """

      result = VariableResolver.resolve_variables(sql)

      # Should use "users" as primary table (first in FROM)
      assert [%{variable: "user_id", table: "users"}] = result
    end
  end

  describe "resolve_variables/1 precedence and deduplication" do
    test "explicit binding takes precedence over implicit" do
      sql = """
      SELECT * FROM users
      WHERE users.id = {{user_id}}
        AND id = {{user_id}}
      """

      result = VariableResolver.resolve_variables(sql)

      # Should only have one binding (deduplicated)
      assert length(result) == 1
      assert [%{variable: "user_id", table: "users", column: "id"}] = result
    end

    test "deduplicates by variable name" do
      sql = """
      SELECT * FROM users
      WHERE users.id = {{id}} OR users.backup_id = {{id}}
      """

      result = VariableResolver.resolve_variables(sql)

      # Only first occurrence kept
      assert length(result) == 1
      assert [%{variable: "id"}] = result
    end
  end

  describe "resolve_variables/1 edge cases" do
    test "handles SQL with no variables" do
      sql = "SELECT * FROM users WHERE active = true"

      result = VariableResolver.resolve_variables(sql)

      assert result == []
    end

    test "handles SQL with single-line comments" do
      sql = """
      SELECT * FROM users
      -- This is a comment with {{fake_var}}
      WHERE users.id = {{real_id}}
      """

      result = VariableResolver.resolve_variables(sql)

      # Should only find real_id, not fake_var in comment
      assert [%{variable: "real_id"}] = result
    end

    test "handles SQL with multi-line comments" do
      sql = """
      SELECT * FROM users
      /* This is a comment
         with {{fake_var}} inside */
      WHERE users.id = {{real_id}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "real_id"}] = result
    end

    test "handles case-insensitive SQL keywords" do
      sql = "select * FROM Users WHERE users.id = {{user_id}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "user_id", table: "users"}] = result
    end

    test "handles extra whitespace" do
      sql = "SELECT   *   FROM   users   WHERE   users.id   =   {{user_id}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "user_id", table: "users", column: "id"}] = result
    end

    test "returns nil table and column when no FROM clause" do
      sql = "SELECT {{value}} + 1"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "value", table: nil, column: nil}] = result
    end

    test "handles variable names with underscores and numbers" do
      sql = "SELECT * FROM users WHERE users.org_id_2 = {{org_id_2}}"

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "org_id_2", column: "org_id_2"}] = result
    end
  end

  describe "resolve_variables/1 with complex queries" do
    test "handles subqueries" do
      sql = """
      SELECT * FROM users
      WHERE users.org_id = {{org_id}}
        AND users.id IN (SELECT user_id FROM admins)
      """

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "org_id", table: "users"}] = result
    end

    test "handles INSERT statements" do
      sql = """
      INSERT INTO users (name, email)
      VALUES ({{name}}, {{email}})
      """

      result = VariableResolver.resolve_variables(sql)

      # INSERT doesn't have WHERE clause with column = {{var}} pattern
      # These are unbound variables with nil column
      assert length(result) == 2
      assert Enum.any?(result, &(&1.variable == "name"))
      assert Enum.any?(result, &(&1.variable == "email"))
    end

    test "handles UPDATE statements" do
      sql = """
      UPDATE users SET name = {{new_name}}
      WHERE users.id = {{user_id}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert Enum.any?(result, &(&1.variable == "user_id" and &1.table == "users"))
    end

    test "handles CTEs (WITH clause)" do
      sql = """
      WITH active_users AS (
        SELECT * FROM users WHERE status = 'active'
      )
      SELECT * FROM active_users WHERE active_users.org_id = {{org_id}}
      """

      result = VariableResolver.resolve_variables(sql)

      assert [%{variable: "org_id", table: "active_users"}] = result
    end
  end
end
