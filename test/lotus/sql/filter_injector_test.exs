defmodule Lotus.SQL.FilterInjectorTest do
  use ExUnit.Case, async: true

  alias Lotus.Query.Filter
  alias Lotus.SQL.FilterInjector

  defp double_quote(id), do: ~s("#{id}")
  defp backtick_quote(id), do: "`#{id}`"

  describe "apply/3" do
    test "returns original SQL when filters is empty" do
      sql = "SELECT * FROM users"
      assert FilterInjector.apply(sql, [], &double_quote/1) == sql
    end

    test "wraps SQL in CTE with single eq filter" do
      sql = "SELECT * FROM users"
      filters = [Filter.new("region", :eq, "US")]

      result = FilterInjector.apply(sql, filters, &double_quote/1)

      assert result ==
               ~s[WITH _base AS (SELECT * FROM users) SELECT * FROM _base WHERE "region" = 'US']
    end

    test "handles multiple filters with AND" do
      sql = "SELECT * FROM orders"

      filters = [
        Filter.new("region", :eq, "US"),
        Filter.new("status", :neq, "cancelled")
      ]

      result = FilterInjector.apply(sql, filters, &double_quote/1)

      assert result ==
               ~s[WITH _base AS (SELECT * FROM orders) SELECT * FROM _base WHERE "region" = 'US' AND "status" != 'cancelled']
    end

    test "handles numeric values without quotes" do
      filters = [Filter.new("price", :gt, 100)]
      result = FilterInjector.apply("SELECT * FROM products", filters, &double_quote/1)
      assert result =~ ~s("price" > 100)
    end

    test "handles float values" do
      filters = [Filter.new("rating", :gte, 4.5)]
      result = FilterInjector.apply("SELECT * FROM reviews", filters, &double_quote/1)
      assert result =~ ~s("rating" >= 4.5)
    end

    test "handles IS NULL operator" do
      filters = [Filter.new("deleted_at", :is_null)]
      result = FilterInjector.apply("SELECT * FROM users", filters, &double_quote/1)
      assert result =~ ~s("deleted_at" IS NULL)
    end

    test "handles IS NOT NULL operator" do
      filters = [Filter.new("email", :is_not_null)]
      result = FilterInjector.apply("SELECT * FROM users", filters, &double_quote/1)
      assert result =~ ~s("email" IS NOT NULL)
    end

    test "handles LIKE operator" do
      filters = [Filter.new("name", :like, "%John%")]
      result = FilterInjector.apply("SELECT * FROM users", filters, &double_quote/1)
      assert result =~ ~s("name" LIKE '%John%')
    end

    test "escapes single quotes in string values" do
      filters = [Filter.new("name", :eq, "O'Brien")]
      result = FilterInjector.apply("SELECT * FROM users", filters, &double_quote/1)
      assert result =~ ~s("name" = 'O''Brien')
    end

    test "handles boolean values" do
      filters = [Filter.new("active", :eq, true)]
      result = FilterInjector.apply("SELECT * FROM users", filters, &double_quote/1)
      assert result =~ ~s("active" = TRUE)
    end

    test "works with backtick quoting (MySQL style)" do
      filters = [Filter.new("region", :eq, "US")]
      result = FilterInjector.apply("SELECT * FROM users", filters, &backtick_quote/1)

      assert result ==
               "WITH _base AS (SELECT * FROM users) SELECT * FROM _base WHERE `region` = 'US'"
    end

    test "escapes double quotes in column names" do
      quote_fn = fn id ->
        escaped = String.replace(id, "\"", "\"\"")
        ~s("#{escaped}")
      end

      filters = [Filter.new(~s(col"name), :eq, "val")]
      result = FilterInjector.apply("SELECT * FROM t", filters, quote_fn)
      assert result =~ ~s("col""name" = 'val')
    end

    test "handles all comparison operators" do
      ops = [eq: "=", neq: "!=", gt: ">", lt: "<", gte: ">=", lte: "<=", like: "LIKE"]

      for {op, sql_op} <- ops do
        filters = [Filter.new("col", op, "val")]
        result = FilterInjector.apply("SELECT 1", filters, &double_quote/1)
        assert result =~ ~s("col" #{sql_op} 'val'), "Failed for op: #{op}"
      end
    end

    test "wraps complex queries safely" do
      sql =
        "SELECT a.*, b.name FROM a JOIN b ON a.id = b.a_id WHERE a.active = true UNION SELECT c.*, d.name FROM c JOIN d ON c.id = d.c_id"

      filters = [Filter.new("name", :eq, "test")]

      result = FilterInjector.apply(sql, filters, &double_quote/1)
      assert result =~ "WITH _base AS (#{sql})"
      assert result =~ ~s(SELECT * FROM _base WHERE "name" = 'test')
    end
  end
end
