defmodule Lotus.AI.Prompts.SQLGenerationTest do
  use Lotus.Case, async: true

  alias Lotus.AI.Prompts.SQLGeneration

  describe "system_prompt/2" do
    test "includes database type" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users", "posts"])

      assert prompt =~ "postgres databases"
    end

    test "includes table names" do
      tables = ["users", "posts", "comments"]
      prompt = SQLGeneration.system_prompt(:postgres, tables)

      assert prompt =~ "users, posts, comments"
    end

    test "includes PostgreSQL-specific notes" do
      prompt = SQLGeneration.system_prompt(:postgres, [])

      assert prompt =~ "double quotes for identifiers"
      assert prompt =~ "arrays, JSON"
      assert prompt =~ "DATE_TRUNC"
    end

    test "includes MySQL-specific notes" do
      prompt = SQLGeneration.system_prompt(:mysql, [])

      assert prompt =~ "backticks for identifiers"
      assert prompt =~ "No array support"
      assert prompt =~ "DATE_FORMAT"
    end

    test "includes SQLite-specific notes" do
      prompt = SQLGeneration.system_prompt(:sqlite, [])

      assert prompt =~ "double quotes for identifiers"
      assert prompt =~ "dynamic typing"
      assert prompt =~ "strftime"
    end

    test "includes generic notes for other databases" do
      prompt = SQLGeneration.system_prompt(:other, [])

      assert prompt =~ "standard SQL syntax"
    end

    test "instructs on tool usage" do
      prompt = SQLGeneration.system_prompt(:postgres, [])

      assert prompt =~ "list_tables()"
      assert prompt =~ "get_table_schema(table_name)"
    end

    test "instructs on handling non-SQL questions" do
      prompt = SQLGeneration.system_prompt(:postgres, [])

      assert prompt =~ "UNABLE_TO_GENERATE"
      assert prompt =~ "weather"
      assert prompt =~ "recipes"
      assert prompt =~ "Send email"
    end

    test "includes SQL formatting guidelines" do
      prompt = SQLGeneration.system_prompt(:postgres, [])

      assert prompt =~ "```sql blocks"
      assert prompt =~ "LIMIT for safety"
      assert prompt =~ "JOINs for multi-table"
    end
  end

  describe "system_prompt/2 variable documentation" do
    test "includes variable syntax docs" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users"])

      assert prompt =~ "{{variable_name}}"
    end

    test "includes widget types" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users"])

      assert prompt =~ "input"
      assert prompt =~ "select"
    end

    test "includes response format guidance" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users"])

      assert prompt =~ "```variables"
      assert prompt =~ "```sql"
    end

    test "includes usage guidelines about not adding variables proactively" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users"])

      assert prompt =~ "NEVER add variables proactively"
    end

    test "includes options strategy guidance" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users"])

      assert prompt =~ "static_options"
      assert prompt =~ "options_query"
      assert prompt =~ "get_column_values()"
    end

    test "includes options_query format requirement" do
      prompt = SQLGeneration.system_prompt(:postgres, ["users"])

      assert prompt =~ "value"
      assert prompt =~ "label"
    end
  end

  describe "extract_sql/1" do
    test "extracts SQL from markdown code blocks" do
      content = """
      ```sql
      SELECT * FROM users
      WHERE created_at >= NOW() - INTERVAL '30 days'
      ```
      """

      assert {:ok, sql} = SQLGeneration.extract_sql(content)
      assert sql == "SELECT * FROM users\nWHERE created_at >= NOW() - INTERVAL '30 days'"
    end

    test "extracts plain SQL without markdown" do
      content = "SELECT COUNT(*) FROM users"

      assert {:ok, sql} = SQLGeneration.extract_sql(content)
      assert sql == "SELECT COUNT(*) FROM users"
    end

    test "trims whitespace from SQL" do
      content = """


      ```sql
      SELECT * FROM users
      ```


      """

      assert {:ok, sql} = SQLGeneration.extract_sql(content)
      assert sql == "SELECT * FROM users"
    end

    test "handles multiline SQL in code blocks" do
      content = """
      ```sql
      SELECT
        u.name,
        COUNT(p.id) AS post_count
      FROM users u
      LEFT JOIN posts p ON u.id = p.user_id
      GROUP BY u.name
      ORDER BY post_count DESC
      LIMIT 10
      ```
      """

      assert {:ok, sql} = SQLGeneration.extract_sql(content)
      assert sql =~ "SELECT"
      assert sql =~ "LEFT JOIN"
      assert sql =~ "GROUP BY"
    end

    test "returns error tuple for UNABLE_TO_GENERATE responses" do
      content = "UNABLE_TO_GENERATE: This is a weather question, not a database query"

      assert {:error, {:unable_to_generate, reason}} = SQLGeneration.extract_sql(content)
      assert reason == "This is a weather question, not a database query"
    end

    test "returns error tuple for refusals with extra context" do
      content =
        "UNABLE_TO_GENERATE: The question asks about company org chart which is not in the database tables"

      assert {:error, {:unable_to_generate, reason}} = SQLGeneration.extract_sql(content)
      assert reason =~ "org chart"
    end

    test "handles edge case with whitespace before UNABLE_TO_GENERATE" do
      content = "  \n  UNABLE_TO_GENERATE: Some reason  \n  "

      assert {:error, {:unable_to_generate, reason}} = SQLGeneration.extract_sql(content)
      assert reason == "Some reason"
    end
  end

  describe "extract_variables/1" do
    test "extracts variables from valid JSON block" do
      content = """
      ```sql
      SELECT * FROM orders WHERE status = {{status}}
      ```

      ```variables
      [{"name": "status", "type": "text", "widget": "select", "label": "Status"}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert length(variables) == 1
      assert hd(variables)["name"] == "status"
      assert hd(variables)["type"] == "text"
      assert hd(variables)["widget"] == "select"
      assert hd(variables)["label"] == "Status"
    end

    test "returns empty list when no variables block" do
      content = """
      ```sql
      SELECT * FROM users
      ```
      """

      assert SQLGeneration.extract_variables(content) == []
    end

    test "returns empty list for malformed JSON" do
      content = """
      ```variables
      {not valid json
      ```
      """

      assert SQLGeneration.extract_variables(content) == []
    end

    test "returns empty list when JSON is not an array" do
      content = """
      ```variables
      {"name": "status"}
      ```
      """

      assert SQLGeneration.extract_variables(content) == []
    end

    test "normalizes unknown types to text" do
      content = """
      ```variables
      [{"name": "foo", "type": "boolean"}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert hd(variables)["type"] == "text"
    end

    test "preserves valid types" do
      content = """
      ```variables
      [
        {"name": "a", "type": "text"},
        {"name": "b", "type": "number"},
        {"name": "c", "type": "date"}
      ]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert Enum.at(variables, 0)["type"] == "text"
      assert Enum.at(variables, 1)["type"] == "number"
      assert Enum.at(variables, 2)["type"] == "date"
    end

    test "defaults widget to input" do
      content = """
      ```variables
      [{"name": "value", "type": "number"}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert hd(variables)["widget"] == "input"
    end

    test "defaults list to false" do
      content = """
      ```variables
      [{"name": "value", "type": "text"}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert hd(variables)["list"] == false
    end

    test "preserves static_options" do
      content = """
      ```variables
      [{"name": "status", "type": "text", "widget": "select", "static_options": [{"value": "a", "label": "A"}]}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)
      options = hd(variables)["static_options"]

      assert length(options) == 1
      assert hd(options)["value"] == "a"
      assert hd(options)["label"] == "A"
    end

    test "preserves options_query" do
      content = """
      ```variables
      [{"name": "user", "type": "text", "widget": "select", "options_query": "SELECT id AS value, name AS label FROM users"}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert hd(variables)["options_query"] == "SELECT id AS value, name AS label FROM users"
    end

    test "preserves list flag when true" do
      content = """
      ```variables
      [{"name": "statuses", "type": "text", "widget": "select", "list": true}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      assert hd(variables)["list"] == true
    end

    test "strips nil values" do
      content = """
      ```variables
      [{"name": "x", "type": "text", "default": null}]
      ```
      """

      variables = SQLGeneration.extract_variables(content)

      refute Map.has_key?(hd(variables), "default")
    end
  end

  describe "extract_response/1" do
    test "extracts both SQL and variables" do
      content = """
      ```sql
      SELECT * FROM orders WHERE status = {{status}}
      ```

      ```variables
      [{"name": "status", "type": "text", "widget": "select"}]
      ```
      """

      assert {:ok, %{sql: sql, variables: variables}} = SQLGeneration.extract_response(content)

      assert sql =~ "SELECT * FROM orders"
      assert length(variables) == 1
      assert hd(variables)["name"] == "status"
    end

    test "returns empty variables for SQL-only responses" do
      content = """
      ```sql
      SELECT * FROM users
      ```
      """

      assert {:ok, %{sql: sql, variables: variables}} = SQLGeneration.extract_response(content)

      assert sql == "SELECT * FROM users"
      assert variables == []
    end

    test "propagates UNABLE_TO_GENERATE errors" do
      content = "UNABLE_TO_GENERATE: Not a database question"

      assert {:error, {:unable_to_generate, reason}} = SQLGeneration.extract_response(content)
      assert reason == "Not a database question"
    end
  end
end
