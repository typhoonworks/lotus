defmodule Lotus.AIFixtures do
  @moduledoc """
  Test fixtures for AI module testing.

  Provides canned responses for LLM interactions without calling real APIs.
  """

  @doc """
  Successful SQL generation response from LLM.
  """
  def successful_sql_response do
    %{
      content: """
      ```sql
      SELECT * FROM users
      WHERE created_at >= NOW() - INTERVAL '30 days'
        AND status = 'active'
      ORDER BY created_at DESC
      LIMIT 100
      ```
      """,
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 150,
        "completion_tokens" => 50,
        "total_tokens" => 200
      }
    }
  end

  @doc """
  Response when LLM refuses to generate SQL (non-SQL question).
  """
  def unable_to_generate_response do
    %{
      content: "UNABLE_TO_GENERATE: This is a weather question, not a database query",
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 100,
        "completion_tokens" => 20,
        "total_tokens" => 120
      }
    }
  end

  @doc """
  SQL without markdown wrapper.
  """
  def plain_sql_response do
    %{
      content: "SELECT COUNT(*) FROM users WHERE status = 'active'",
      model: "claude-opus-4",
      usage: %{
        "input_tokens" => 120,
        "output_tokens" => 30
      }
    }
  end

  @doc """
  Complex SQL with JOINs.
  """
  def complex_sql_response do
    %{
      content: """
      ```sql
      SELECT
        p.name AS product_name,
        COUNT(o.id) AS order_count,
        SUM(o.total) AS revenue
      FROM products p
      LEFT JOIN orders o ON p.id = o.product_id
      WHERE o.created_at >= '2024-01-01'
      GROUP BY p.name
      ORDER BY revenue DESC
      LIMIT 10
      ```
      """,
      model: "gemini-2.0-flash-exp",
      usage: %{
        "promptTokenCount" => 200,
        "candidatesTokenCount" => 80,
        "totalTokenCount" => 280
      }
    }
  end

  @doc """
  Table list for schema introspection.
  """
  def table_list do
    [
      {"public", "users"},
      {"public", "posts"},
      {"public", "comments"},
      {"analytics", "events"}
    ]
  end

  @doc """
  Schema-less table list (SQLite).
  """
  def sqlite_table_list do
    ["users", "posts", "comments"]
  end

  @doc """
  Column schema for users table.
  """
  def users_table_schema do
    [
      %{name: "id", type: "integer", nullable: false, primary_key: true},
      %{name: "email", type: "varchar", nullable: false, primary_key: false},
      %{name: "created_at", type: "timestamp", nullable: false, primary_key: false},
      %{name: "status", type: "varchar", nullable: true, primary_key: false}
    ]
  end

  @doc """
  Expected JSON-encoded table list.
  """
  def encoded_table_list do
    Lotus.JSON.encode!(%{tables: ["users", "posts", "comments", "events"]})
  end

  @doc """
  Expected JSON-encoded table schema.
  """
  def encoded_users_schema do
    Lotus.JSON.encode!(%{
      table: "users",
      columns: [
        %{name: "id", type: "integer", nullable: false, primary_key: true},
        %{name: "email", type: "varchar", nullable: false, primary_key: false},
        %{name: "created_at", type: "timestamp", nullable: false, primary_key: false},
        %{name: "status", type: "varchar", nullable: true, primary_key: false}
      ]
    })
  end
end
