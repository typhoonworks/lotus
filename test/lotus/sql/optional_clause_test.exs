defmodule Lotus.SQL.OptionalClauseTest do
  use ExUnit.Case, async: true

  alias Lotus.SQL.OptionalClause

  describe "process/2" do
    test "passes through SQL with no brackets" do
      sql = "SELECT * FROM users WHERE id = {{id}}"
      assert OptionalClause.process(sql, %{"id" => "1"}) == sql
    end

    test "keeps clause when value is provided" do
      sql = "SELECT * FROM users WHERE 1=1 [[AND name = {{name}}]]"
      result = OptionalClause.process(sql, %{"name" => "John"})
      assert result == "SELECT * FROM users WHERE 1=1 AND name = {{name}}"
    end

    test "removes clause when value is missing" do
      sql = "SELECT * FROM users WHERE 1=1 [[AND name = {{name}}]]"
      result = OptionalClause.process(sql, %{})
      assert result == "SELECT * FROM users WHERE 1=1 "
    end

    test "removes clause when value is nil" do
      sql = "SELECT * FROM users WHERE 1=1 [[AND name = {{name}}]]"
      result = OptionalClause.process(sql, %{"name" => nil})
      assert result == "SELECT * FROM users WHERE 1=1 "
    end

    test "removes clause when value is empty string" do
      sql = "SELECT * FROM users WHERE 1=1 [[AND name = {{name}}]]"
      result = OptionalClause.process(sql, %{"name" => ""})
      assert result == "SELECT * FROM users WHERE 1=1 "
    end

    test "handles multiple blocks with mixed provided/missing values" do
      sql = """
      SELECT * FROM users
      WHERE 1=1
        [[AND name = {{name}}]]
        [[AND status = {{status}}]]
      ORDER BY id\
      """

      result = OptionalClause.process(sql, %{"status" => "active"})

      assert result == """
             SELECT * FROM users
             WHERE 1=1
               \n  AND status = {{status}}
             ORDER BY id\
             """
    end

    test "block with multiple variables requires all to have values" do
      sql = "SELECT * FROM users WHERE 1=1 [[AND age BETWEEN {{min_age}} AND {{max_age}}]]"

      # Only one provided — block removed
      result = OptionalClause.process(sql, %{"min_age" => "18"})
      assert result == "SELECT * FROM users WHERE 1=1 "

      # Both provided — block kept
      result = OptionalClause.process(sql, %{"min_age" => "18", "max_age" => "65"})
      assert result == "SELECT * FROM users WHERE 1=1 AND age BETWEEN {{min_age}} AND {{max_age}}"
    end

    test "variable appearing both inside and outside brackets" do
      sql = "SELECT * FROM users WHERE id = {{id}} [[AND name = {{name}}]]"

      # name missing — optional block removed, but id (outside) stays
      result = OptionalClause.process(sql, %{"id" => "1"})
      assert result == "SELECT * FROM users WHERE id = {{id}} "
    end

    test "handles ILIKE pattern with concatenation" do
      sql =
        "SELECT * FROM users WHERE 1=1 [[AND \"name\" ILIKE '%' || {{name}} || '%']]"

      result = OptionalClause.process(sql, %{"name" => "John"})

      assert result ==
               "SELECT * FROM users WHERE 1=1 AND \"name\" ILIKE '%' || {{name}} || '%'"
    end
  end

  describe "extract_optional_variable_names/1" do
    test "returns empty MapSet when no brackets" do
      sql = "SELECT * FROM users WHERE id = {{id}}"
      assert OptionalClause.extract_optional_variable_names(sql) == MapSet.new()
    end

    test "extracts variable names from optional blocks" do
      sql = "SELECT * FROM users WHERE 1=1 [[AND name = {{name}}]] [[AND status = {{status}}]]"

      assert OptionalClause.extract_optional_variable_names(sql) ==
               MapSet.new(["name", "status"])
    end

    test "does not include variables outside brackets" do
      sql = "SELECT * FROM users WHERE id = {{id}} [[AND name = {{name}}]]"
      assert OptionalClause.extract_optional_variable_names(sql) == MapSet.new(["name"])
    end

    test "deduplicates variable names" do
      sql = "SELECT * FROM users [[AND name = {{name}}]] [[AND nick = {{name}}]]"
      assert OptionalClause.extract_optional_variable_names(sql) == MapSet.new(["name"])
    end
  end
end
