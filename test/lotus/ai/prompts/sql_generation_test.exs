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
end
