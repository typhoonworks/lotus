defmodule Lotus.Integration.Sqlite.QuotedVarsTest do
  use Lotus.Case, async: false

  @moduletag :sqlite

  alias Lotus.Fixtures
  alias Lotus.Storage.Query
  alias Lotus.Test.SqliteRepo

  setup do
    user1 = Fixtures.insert_user(%{name: "Test User", email: "test@example.com"}, SqliteRepo)
    user2 = Fixtures.insert_user(%{name: "John Doe", email: "john@example.com"}, SqliteRepo)
    user3 = Fixtures.insert_user(%{name: "Jane Smith", email: "jane@example.com"}, SqliteRepo)

    %{user1: user1, user2: user2, user3: user3}
  end

  describe "SQLite quoted scalar variables" do
    test "strips quotes from '{{name}}'" do
      query = %Query{
        statement: """
        SELECT name, email
        FROM test_users
        WHERE name = '{{name}}'
        """,
        variables: [%{name: "name", type: :text, default: nil}],
        data_repo: "sqlite"
      }

      result = Lotus.run_query(query, vars: %{"name" => "John Doe"})

      assert {:ok, %{columns: ["name", "email"], rows: rows}} = result
      assert length(rows) == 1
      assert [["John Doe", "john@example.com"]] = rows
    end

    test "does NOT strip quotes from wildcards '%{{q}}%'" do
      query = %Query{
        statement: """
        SELECT name
        FROM test_users
        WHERE name LIKE '%{{q}}%'
        ORDER BY name
        """,
        variables: [%{name: "q", type: :text, default: nil}],
        data_repo: "sqlite"
      }

      result = Lotus.run_query(query, vars: %{"q" => "John"})

      assert {:ok, %{columns: ["name"], rows: rows}} = result
      assert length(rows) == 1
      assert [["John Doe"]] = rows
    end
  end
end
