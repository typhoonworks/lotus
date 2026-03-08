defmodule Lotus.SQL.SortInjectorTest do
  use ExUnit.Case, async: true

  alias Lotus.Query.Sort
  alias Lotus.SQL.SortInjector

  defp double_quote(id), do: ~s("#{id}")
  defp backtick_quote(id), do: "`#{id}`"

  describe "apply/3" do
    test "returns original SQL when sorts is empty" do
      sql = "SELECT * FROM users"
      assert SortInjector.apply(sql, [], &double_quote/1) == sql
    end

    test "wraps SQL in CTE with single asc sort" do
      sql = "SELECT * FROM users"
      sorts = [Sort.new("name", :asc)]

      result = SortInjector.apply(sql, sorts, &double_quote/1)

      assert result ==
               ~s[WITH _sorted AS (SELECT * FROM users) SELECT * FROM _sorted ORDER BY "name" ASC]
    end

    test "wraps SQL in CTE with single desc sort" do
      sql = "SELECT * FROM users"
      sorts = [Sort.new("created_at", :desc)]

      result = SortInjector.apply(sql, sorts, &double_quote/1)

      assert result ==
               ~s[WITH _sorted AS (SELECT * FROM users) SELECT * FROM _sorted ORDER BY "created_at" DESC]
    end

    test "handles multiple sorts" do
      sql = "SELECT * FROM orders"

      sorts = [
        Sort.new("status", :asc),
        Sort.new("created_at", :desc)
      ]

      result = SortInjector.apply(sql, sorts, &double_quote/1)

      assert result ==
               ~s[WITH _sorted AS (SELECT * FROM orders) SELECT * FROM _sorted ORDER BY "status" ASC, "created_at" DESC]
    end

    test "works with backtick quoting (MySQL style)" do
      sorts = [Sort.new("name", :asc)]
      result = SortInjector.apply("SELECT * FROM users", sorts, &backtick_quote/1)

      assert result ==
               "WITH _sorted AS (SELECT * FROM users) SELECT * FROM _sorted ORDER BY `name` ASC"
    end

    test "escapes double quotes in column names" do
      quote_fn = fn id ->
        escaped = String.replace(id, "\"", "\"\"")
        ~s("#{escaped}")
      end

      sorts = [Sort.new(~s(col"name), :desc)]
      result = SortInjector.apply("SELECT * FROM t", sorts, quote_fn)
      assert result =~ ~s("col""name" DESC)
    end

    test "safely wraps queries that already have ORDER BY" do
      sql = "SELECT * FROM users ORDER BY id"
      sorts = [Sort.new("name", :desc)]

      result = SortInjector.apply(sql, sorts, &double_quote/1)

      assert result ==
               ~s[WITH _sorted AS (SELECT * FROM users ORDER BY id) SELECT * FROM _sorted ORDER BY "name" DESC]
    end

    test "works after CTE-wrapped filtered query" do
      sql =
        ~s[WITH _base AS (SELECT * FROM users) SELECT * FROM _base WHERE "region" = 'US']

      sorts = [Sort.new("name", :asc)]
      result = SortInjector.apply(sql, sorts, &double_quote/1)

      assert result ==
               ~s[WITH _sorted AS (WITH _base AS (SELECT * FROM users) SELECT * FROM _base WHERE "region" = 'US') SELECT * FROM _sorted ORDER BY "name" ASC]
    end
  end
end
