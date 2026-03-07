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
  SQL response with variable configurations.
  """
  def sql_with_variables_response do
    %{
      content: """
      ```sql
      SELECT * FROM orders WHERE status = {{status}}
      ```

      ```variables
      [
        {
          "name": "status",
          "type": "text",
          "widget": "select",
          "label": "Order Status",
          "static_options": [
            {"value": "pending", "label": "Pending"},
            {"value": "shipped", "label": "Shipped"},
            {"value": "delivered", "label": "Delivered"}
          ]
        }
      ]
      ```
      """,
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 200,
        "completion_tokens" => 80,
        "total_tokens" => 280
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

  @doc """
  Optimization suggestions response with multiple suggestions.
  """
  def optimization_suggestions_response do
    %{
      content: """
      ```json
      [
        {
          "type": "index",
          "impact": "high",
          "title": "Add index on orders.created_at",
          "suggestion": "The query performs a sequential scan on the orders table filtered by created_at. Adding an index would allow an index scan instead.\\n\\nCREATE INDEX idx_orders_created_at ON orders (created_at);"
        },
        {
          "type": "rewrite",
          "impact": "medium",
          "title": "Select only needed columns instead of SELECT *",
          "suggestion": "You're selecting all columns with SELECT * but may only need specific columns. Selecting only needed columns reduces I/O."
        }
      ]
      ```
      """,
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 500,
        "completion_tokens" => 200,
        "total_tokens" => 700
      }
    }
  end

  @doc """
  Optimization response indicating the query is already well-optimized.
  """
  def no_optimizations_response do
    %{
      content: "[]",
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 400,
        "completion_tokens" => 10,
        "total_tokens" => 410
      }
    }
  end

  @doc """
  Explanation response for a full query.
  """
  def explanation_response do
    %{
      content:
        "This query retrieves all rows from the orders table where the order was created after January 1st, 2024. It returns every column for matching orders, sorted by the database's default order.",
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 300,
        "completion_tokens" => 100,
        "total_tokens" => 400
      }
    }
  end

  @doc """
  Explanation response for a query fragment.
  """
  def fragment_explanation_response do
    %{
      content:
        "This LEFT JOIN connects the departments table to the employees table by matching each department's id with the employee's department_id. It keeps all departments in the result even if they have no employees.",
      model: "gpt-4o",
      usage: %{
        "prompt_tokens" => 350,
        "completion_tokens" => 120,
        "total_tokens" => 470
      }
    }
  end

  @doc """
  Sample PostgreSQL execution plan (JSON format).
  """
  def postgres_explain_plan do
    Lotus.JSON.encode!([
      %{
        "Plan" => %{
          "Node Type" => "Seq Scan",
          "Relation Name" => "orders",
          "Schema" => "public",
          "Alias" => "orders",
          "Startup Cost" => 0.0,
          "Total Cost" => 1234.56,
          "Plan Rows" => 50_000,
          "Plan Width" => 200,
          "Filter" => "(created_at > '2024-01-01'::date)"
        }
      }
    ])
  end
end
