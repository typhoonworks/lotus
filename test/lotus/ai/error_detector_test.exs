defmodule Lotus.AI.ErrorDetectorTest do
  use ExUnit.Case, async: true

  alias Lotus.AI.ErrorDetector

  doctest Lotus.AI.ErrorDetector

  describe "classify_error/1" do
    test "identifies column not found errors" do
      assert ErrorDetector.classify_error("column 'status' does not exist") == :column_not_found
      assert ErrorDetector.classify_error("ERROR: column 'foo' not found") == :column_not_found

      assert ErrorDetector.classify_error("Unknown column 'bar' in field list") ==
               :column_not_found
    end

    test "identifies table not found errors" do
      assert ErrorDetector.classify_error("relation 'users' does not exist") == :table_not_found
      assert ErrorDetector.classify_error("table 'products' not found") == :table_not_found
      assert ErrorDetector.classify_error("Table 'mydb.orders' doesn't exist") == :table_not_found
    end

    test "identifies syntax errors" do
      assert ErrorDetector.classify_error("syntax error at or near 'SELECT'") == :syntax_error
      assert ErrorDetector.classify_error("Syntax error in SQL statement") == :syntax_error
      assert ErrorDetector.classify_error("unexpected token: FROM") == :syntax_error
    end

    test "identifies type mismatch errors" do
      assert ErrorDetector.classify_error("type mismatch in comparison") == :type_mismatch
      assert ErrorDetector.classify_error("invalid type for operation") == :type_mismatch
      assert ErrorDetector.classify_error("cannot cast type text to integer") == :type_mismatch
    end

    test "identifies ambiguous column errors" do
      assert ErrorDetector.classify_error("column reference 'id' is ambiguous") ==
               :ambiguous_column

      assert ErrorDetector.classify_error("Ambiguous column name: 'name'") == :ambiguous_column
    end

    test "identifies permission errors" do
      assert ErrorDetector.classify_error("permission denied for table users") ==
               :permission_denied

      assert ErrorDetector.classify_error("access denied to column 'salary'") ==
               :permission_denied

      assert ErrorDetector.classify_error("not authorized to access table") == :permission_denied
    end

    test "classifies unknown errors" do
      assert ErrorDetector.classify_error("some random database error") == :unknown
      assert ErrorDetector.classify_error("connection timeout") == :unknown
    end

    test "is case insensitive" do
      assert ErrorDetector.classify_error("COLUMN 'foo' DOES NOT EXIST") == :column_not_found
      assert ErrorDetector.classify_error("Syntax Error at line 5") == :syntax_error
    end
  end

  describe "analyze_error/3" do
    test "provides context for column not found errors" do
      result =
        ErrorDetector.analyze_error(
          "column 'status' does not exist",
          "SELECT status FROM users",
          %{tables_analyzed: ["users"]}
        )

      assert result.error_type == :column_not_found
      assert result.error_message == "column 'status' does not exist"
      assert result.failed_sql == "SELECT status FROM users"
      assert result.suggestions != []
      assert Enum.any?(result.suggestions, &String.contains?(&1, "get_table_schema"))
    end

    test "provides context for table not found errors" do
      result =
        ErrorDetector.analyze_error(
          "relation 'products' does not exist",
          "SELECT * FROM products",
          %{}
        )

      assert result.error_type == :table_not_found
      assert Enum.any?(result.suggestions, &String.contains?(&1, "list_tables()"))
      assert Enum.any?(result.suggestions, &String.contains?(&1, "schema-qualified"))
    end

    test "provides context for syntax errors" do
      result =
        ErrorDetector.analyze_error(
          "syntax error at or near 'FROM'",
          "SELECT FROM users",
          %{}
        )

      assert result.error_type == :syntax_error
      assert Enum.any?(result.suggestions, &String.contains?(&1, "syntax"))
    end

    test "provides context for type mismatch errors" do
      result =
        ErrorDetector.analyze_error(
          "type mismatch: cannot compare integer with text",
          "SELECT * FROM users WHERE id = 'abc'",
          %{}
        )

      assert result.error_type == :type_mismatch
      assert Enum.any?(result.suggestions, &String.contains?(&1, "type"))
      assert Enum.any?(result.suggestions, &String.contains?(&1, "cast"))
    end

    test "provides context for ambiguous column errors" do
      result =
        ErrorDetector.analyze_error(
          "column 'id' is ambiguous",
          "SELECT id FROM users JOIN orders ON users.id = orders.user_id",
          %{}
        )

      assert result.error_type == :ambiguous_column
      assert Enum.any?(result.suggestions, &String.contains?(&1, "ambiguous"))
      assert Enum.any?(result.suggestions, &String.contains?(&1, "Qualify"))
    end

    test "works without SQL or schema context" do
      result = ErrorDetector.analyze_error("some error", nil, %{})

      assert result.error_type == :unknown
      assert result.failed_sql == nil
      assert result.suggestions != []
    end
  end

  describe "suggest_fixes/4" do
    test "suggests fixes for column not found with schema context" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :column_not_found,
          "column 'status' does not exist",
          "SELECT status FROM users",
          %{tables_analyzed: ["users", "orders"]}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "get_table_schema('users')"))
      assert Enum.any?(suggestions, &String.contains?(&1, "different name"))
    end

    test "suggests fixes for column not found without schema context" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :column_not_found,
          "column 'foo' does not exist",
          "SELECT foo FROM bar",
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "get_table_schema()"))
      assert Enum.any?(suggestions, &String.contains?(&1, "might not exist"))
    end

    test "suggests fixes for table not found" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :table_not_found,
          "table 'products' does not exist",
          "SELECT * FROM products",
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "list_tables()"))
      assert Enum.any?(suggestions, &String.contains?(&1, "schema-qualified"))
      assert Enum.any?(suggestions, &String.contains?(&1, "products"))
    end

    test "suggests fixes for syntax errors" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :syntax_error,
          "syntax error near 'WHERE'",
          "SELECT * FROM users WHERE",
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "syntax"))
      assert Enum.any?(suggestions, &String.contains?(&1, "Review"))
    end

    test "suggests fixes for syntax errors with near context" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :syntax_error,
          "syntax error at or near 'FROM' at line 5",
          "SELECT FROM users",
          %{}
        )

      assert Enum.any?(suggestions, fn s ->
               String.contains?(s, "near") || String.contains?(s, "syntax")
             end)
    end

    test "suggests fixes for type mismatch" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :type_mismatch,
          "type mismatch",
          nil,
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "type"))
      assert Enum.any?(suggestions, &String.contains?(&1, "cast"))
    end

    test "suggests fixes for ambiguous columns" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :ambiguous_column,
          "column 'id' is ambiguous",
          "SELECT id FROM users JOIN orders",
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "ambiguous"))
      assert Enum.any?(suggestions, &String.contains?(&1, "Qualify"))
      assert Enum.any?(suggestions, &String.contains?(&1, "table_name.id"))
    end

    test "suggests fixes for permission errors" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :permission_denied,
          "permission denied",
          nil,
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "permission"))
      assert Enum.any?(suggestions, &String.contains?(&1, "list_tables()"))
    end

    test "suggests fixes for unknown errors" do
      suggestions =
        ErrorDetector.suggest_fixes(
          :unknown,
          "unexpected database error",
          nil,
          %{}
        )

      assert Enum.any?(suggestions, &String.contains?(&1, "unexpected"))
      assert Enum.any?(suggestions, &String.contains?(&1, "Review"))
    end
  end
end
