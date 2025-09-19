defmodule Lotus.Integration.Sqlite.IntervalQueryTest do
  use Lotus.Case, async: false

  @moduletag :sqlite

  alias Lotus.Fixtures
  alias Lotus.Storage.Query
  alias Lotus.Test.SqliteRepo

  setup do
    user = Fixtures.insert_user(%{name: "Test User"}, SqliteRepo)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Fixtures.insert_post(user.id, %{title: "The Mad Ones", published_at: now}, SqliteRepo)

    Fixtures.insert_post(
      user.id,
      %{title: "First Thought Best Thought", published_at: DateTime.add(now, -5, :day)},
      SqliteRepo
    )

    Fixtures.insert_post(
      user.id,
      %{title: "Notes of a Dirty Old Man", published_at: DateTime.add(now, -10, :day)},
      SqliteRepo
    )

    Fixtures.insert_post(
      user.id,
      %{
        title: "Draft: Fear and Loathing at the Typewriter",
        published_at: DateTime.add(now, -15, :day)
      },
      SqliteRepo
    )

    :ok
  end

  describe "SQLite datetime queries with variable substitution" do
    test "INTERVAL syntax fails on SQLite" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= NOW() - INTERVAL '{{days}} days'
          AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: "sqlite"
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:error, error} = result
      assert error =~ "SQLite Error"
    end

    test "datetime with days variables" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= datetime('now', '-' || CAST({{days}} AS text) || ' days')
        AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "days", type: :number, default: nil}],
        data_repo: "sqlite"
      }

      result = Lotus.run_query(query, vars: %{"days" => 7})

      assert {:ok, %{columns: ["title", "published_at"], rows: rows}} = result
      assert length(rows) == 2
      titles = Enum.map(rows, fn [title, _] -> title end)
      assert "The Mad Ones" in titles
      assert "First Thought Best Thought" in titles
    end

    test "datetime with unit variables" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= datetime('now', '-7 ' || {{unit}})
        AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [%{name: "unit", type: :text, default: nil}],
        data_repo: "sqlite"
      }

      result = Lotus.run_query(query, vars: %{"unit" => "days"})

      assert {:ok, %{columns: ["title", "published_at"], rows: rows}} = result
      assert length(rows) == 2
      titles = Enum.map(rows, fn [title, _] -> title end)
      assert "The Mad Ones" in titles
      assert "First Thought Best Thought" in titles
    end

    test "datetime with days and unit variables" do
      query = %Query{
        statement: """
        SELECT title, published_at
        FROM test_posts
        WHERE published_at >= datetime('now', '-' || CAST({{days}} AS text) || ' ' || {{unit}})
        AND published_at IS NOT NULL
        ORDER BY published_at DESC
        """,
        variables: [
          %{name: "days", type: :number, default: nil},
          %{name: "unit", type: :text, default: nil}
        ],
        data_repo: "sqlite"
      }

      result = Lotus.run_query(query, vars: %{"days" => 7, "unit" => "days"})

      assert {:ok, %{columns: ["title", "published_at"], rows: rows}} = result
      assert length(rows) == 2
      titles = Enum.map(rows, fn [title, _] -> title end)
      assert "The Mad Ones" in titles
      assert "First Thought Best Thought" in titles
    end
  end
end
