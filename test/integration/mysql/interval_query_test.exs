defmodule Lotus.Integration.Mysql.IntervalQueryTest do
  use Lotus.Case, async: false

  @moduletag :mysql

  alias Lotus.Fixtures
  alias Lotus.Storage.Query
  alias Lotus.Test.MysqlRepo

  setup do
    user = Fixtures.insert_user(%{name: "Test User"}, MysqlRepo)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Fixtures.insert_post(user.id, %{title: "The Mad Ones", published_at: now}, MysqlRepo)

    Fixtures.insert_post(
      user.id,
      %{title: "First Thought Best Thought", published_at: DateTime.add(now, -5, :day)},
      MysqlRepo
    )

    Fixtures.insert_post(
      user.id,
      %{title: "Notes of a Dirty Old Man", published_at: DateTime.add(now, -10, :day)},
      MysqlRepo
    )

    Fixtures.insert_post(
      user.id,
      %{
        title: "Draft: Fear and Loathing at the Typewriter",
        published_at: DateTime.add(now, -15, :day)
      },
      MysqlRepo
    )

    :ok
  end

  describe "MySQL INTERVAL queries with variable substitution" do
    test "INTERVAL {{days}} DAY with variables" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL {{days}} DAY
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: "mysql"
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:ok, %{columns: ["title", "published_at"], rows: rows}} = result
      assert length(rows) == 2
      titles = Enum.map(rows, fn [title, _] -> title end)
      assert "The Mad Ones" in titles
      assert "First Thought Best Thought" in titles
    end

    test "PostgreSQL INTERVAL syntax fails on MySQL" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL '{{days}} days'
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: "mysql"
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:error, error} = result
      assert error =~ "MySQL Error"
    end

    test "SQLite datetime syntax fails on MySQL" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= datetime('now', '-' || CAST({{days}} AS CHAR) || ' days')
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: "mysql"
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:error, error} = result
      assert error =~ "MySQL Error"
    end
  end
end
