defmodule Lotus.Integration.Postgres.QuotedVarsTest do
  use Lotus.Case, async: false

  @moduletag :postgres

  alias Lotus.Fixtures
  alias Lotus.Storage.Query
  alias Lotus.Test.Repo

  setup do
    user1 = Fixtures.insert_user(%{name: "Test User", email: "test@example.com"}, Repo)
    user2 = Fixtures.insert_user(%{name: "John Doe", email: "john@example.com"}, Repo)
    user3 = Fixtures.insert_user(%{name: "Jane Smith", email: "jane@example.com"}, Repo)

    %{user1: user1, user2: user2, user3: user3, john_id: user2.id}
  end

  describe "PostgreSQL quoted scalar variables" do
    test "strips quotes from '{{name}}'" do
      query = %Query{
        statement: """
        SELECT name, email
        FROM test_users
        WHERE name = '{{name}}'
        """,
        variables: [%{name: "name", type: :text, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"name" => "John Doe"})

      assert {:ok, %{columns: ["name", "email"], rows: rows}} = result
      assert length(rows) == 1
      assert [["John Doe", "john@example.com"]] = rows
    end

    test "strips quotes from '{{email}}'" do
      query = %Query{
        statement: """
        SELECT name
        FROM test_users
        WHERE email = '{{email}}'
        """,
        variables: [%{name: "email", type: :text, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"email" => "jane@example.com"})

      assert {:ok, %{columns: ["name"], rows: rows}} = result
      assert length(rows) == 1
      assert [["Jane Smith"]] = rows
    end

    test "strips quotes with type casting '{{id}}'::int", %{john_id: john_id} do
      query = %Query{
        statement: """
        SELECT name
        FROM test_users
        WHERE id = '{{user_id}}'::int
        """,
        variables: [%{name: "user_id", type: :number, default: nil}],
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"user_id" => john_id})

      assert {:ok, %{columns: ["name"], rows: rows}} = result
      assert length(rows) == 1
      assert [["John Doe"]] = rows
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
        data_repo: nil
      }

      result = Lotus.run_query(query, vars: %{"q" => "John"})

      assert {:ok, %{columns: ["name"], rows: rows}} = result
      assert length(rows) == 1
      assert [["John Doe"]] = rows
    end
  end
end
