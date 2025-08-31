defmodule Lotus.Integration.Postgres.IntervalQueryTest do
  use Lotus.Case, async: false

  @moduletag :postgres

  alias Lotus.Storage.Query
  alias Lotus.Test.Repo
  alias Lotus.Fixtures

  setup do
    user = Fixtures.insert_user(%{name: "Test User"}, Repo)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Fixtures.insert_post(user.id, %{title: "The Mad Ones", published_at: now}, Repo)

    Fixtures.insert_post(
      user.id,
      %{title: "First Thought Best Thought", published_at: DateTime.add(now, -5, :day)},
      Repo
    )

    Fixtures.insert_post(
      user.id,
      %{title: "Notes of a Dirty Old Man", published_at: DateTime.add(now, -10, :day)},
      Repo
    )

    Fixtures.insert_post(
      user.id,
      %{
        title: "Draft: Fear and Loathing at the Typewriter",
        published_at: DateTime.add(now, -15, :day)
      },
      Repo
    )

    :ok
  end

  describe "PostgreSQL INTERVAL queries with variable substitution" do
    test "INTERVAL '{{days}} days' with variables" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL '{{days}} days'
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:ok, %{columns: ["title", "published_at"], rows: rows}} = result
      assert length(rows) == 2
      titles = Enum.map(rows, fn [title, _] -> title end)
      assert "The Mad Ones" in titles
      assert "First Thought Best Thought" in titles
    end

    test "INTERVAL '{{days}} day' with variables" do
      query = %Query{
        statement: """
        SELECT COUNT(*) as count
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL '{{days}} day'
          AND published_at IS NOT NULL
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"days" => 1})
      assert {:ok, %{columns: ["count"], rows: [[count]]}} = result
      assert count == 1
    end

    test "INTERVAL '7 {{unit}}' with variables" do
      query = %Query{
        statement: """
        SELECT COUNT(*) as count
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL '7 {{unit}}'
          AND published_at IS NOT NULL
        """,
        variables: [%{name: "unit", type: :text, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"unit" => "days"})
      assert {:ok, %{columns: ["count"], rows: [[count]]}} = result
      assert count == 2
    end

    test "INTERVAL '{{days}} {{unit}}' with both variables" do
      query = %Query{
        statement: """
        SELECT COUNT(*) as count
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL '{{days}} {{unit}}'
          AND published_at IS NOT NULL
        """,
        variables: [
          %{name: "days", type: :number, default: nil},
          %{name: "unit", type: :text, default: nil}
        ],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"days" => 7, "unit" => "days"})
      assert {:ok, %{columns: ["count"], rows: [[count]]}} = result
      assert count == 2
    end

    test "INTERVAL {{interval}} with full interval string variable" do
      query = %Query{
        statement: """
        SELECT COUNT(*) as count
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL {{interval}}
          AND published_at IS NOT NULL
        """,
        variables: [
          %{name: "interval", type: :text, default: nil}
        ],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"interval" => "7 days"})
      assert {:ok, %{columns: ["count"], rows: [[count]]}} = result
      assert count == 2
    end

    test "MySQL INTERVAL syntax fails on PostgreSQL" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL {{days}} DAY
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:error, error} = result
      assert error =~ "syntax error" or error =~ "INTERVAL"
    end

    test "SQLite datetime syntax fails on PostgreSQL" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= datetime('now', '-' || CAST({{days}} AS text) || ' days')
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:error, error} = result
      assert error =~ "function datetime" or error =~ "does not exist"
    end
  end
end
