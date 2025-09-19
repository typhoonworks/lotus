defmodule Lotus.Integration.Sqlite.WindowPaginationTest do
  use Lotus.Case, async: false

  @moduletag :sqlite

  alias Lotus.Fixtures
  alias Lotus.Storage.Query
  alias Lotus.Test.SqliteRepo, as: Repo

  setup do
    u1 = Fixtures.insert_user(%{name: "Window A", email: "window_sqlite_1@example.com"}, Repo)
    u2 = Fixtures.insert_user(%{name: "Window B", email: "window_sqlite_2@example.com"}, Repo)
    u3 = Fixtures.insert_user(%{name: "Window C", email: "window_sqlite_3@example.com"}, Repo)

    on_exit(fn ->
      Repo.delete!(u1)
      Repo.delete!(u2)
      Repo.delete!(u3)
    end)

    :ok
  end

  describe "run_sql/3 with window pagination (sqlite)" do
    test "pages results without total count" do
      sql = """
      SELECT name FROM test_users
      WHERE email IN ('window_sqlite_1@example.com','window_sqlite_2@example.com','window_sqlite_3@example.com')
      ORDER BY name
      """

      assert {:ok, result} =
               Lotus.run_sql(sql, [], repo: "sqlite", window: [limit: 1, offset: 0, count: :none])

      assert result.num_rows == 1
      assert result.rows == [["Window A"]]
      assert %{limit: 1, offset: 0} = result.meta[:window]
      assert is_nil(result.meta[:total_count])
      assert result.meta[:total_mode] in [:none, nil]
    end

    test "pages results with exact total count" do
      sql = """
      SELECT name FROM test_users
      WHERE email IN ('window_sqlite_1@example.com','window_sqlite_2@example.com','window_sqlite_3@example.com')
      ORDER BY name
      """

      assert {:ok, result} =
               Lotus.run_sql(sql, [],
                 repo: "sqlite",
                 window: [limit: 2, offset: 1, count: :exact]
               )

      assert result.num_rows == 2
      assert result.rows == [["Window B"], ["Window C"]]
      assert %{limit: 2, offset: 1} = result.meta[:window]
      assert result.meta[:total_count] == 3
      assert result.meta[:total_mode] == :exact
    end
  end

  describe "run_query/2 with window pagination (sqlite)" do
    test "pages results via saved-query struct (no total)" do
      q = %Query{
        statement: """
        SELECT name FROM test_users
        WHERE email IN ('window_sqlite_1@example.com','window_sqlite_2@example.com','window_sqlite_3@example.com')
        ORDER BY name
        """,
        variables: [],
        data_repo: nil
      }

      assert {:ok, result} =
               Lotus.run_query(q, repo: "sqlite", window: [limit: 1, offset: 1, count: :none])

      assert result.num_rows == 1
      assert result.rows == [["Window B"]]
      assert %{limit: 1, offset: 1} = result.meta[:window]
      assert is_nil(result.meta[:total_count])
    end

    test "pages results via saved-query struct (with total)" do
      q = %Query{
        statement: """
        SELECT name FROM test_users
        WHERE email IN ('window_sqlite_1@example.com','window_sqlite_2@example.com','window_sqlite_3@example.com')
        ORDER BY name
        """,
        variables: [],
        data_repo: nil
      }

      assert {:ok, result} =
               Lotus.run_query(q, repo: "sqlite", window: [limit: 2, offset: 0, count: :exact])

      assert result.num_rows == 2
      assert result.rows == [["Window A"], ["Window B"]]
      assert %{limit: 2, offset: 0} = result.meta[:window]
      assert result.meta[:total_count] == 3
      assert result.meta[:total_mode] == :exact
    end
  end
end
