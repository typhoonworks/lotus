defmodule Lotus.AdapterTest do
  use Lotus.Case, async: true

  alias Lotus.Adapter

  describe "execute_in_transaction/3" do
    @tag :postgres
    test "executes PostgreSQL transaction with read-only mode" do
      result =
        Adapter.execute_in_transaction(
          Lotus.Test.Repo,
          fn ->
            Lotus.Test.Repo.query!("SELECT 1 as test_value")
          end,
          read_only: true
        )

      assert {:ok, %{rows: [[1]]}} = result
    end

    @tag :sqlite
    test "executes SQLite transaction with read-only mode" do
      result =
        Adapter.execute_in_transaction(
          Lotus.Test.SqliteRepo,
          fn ->
            Lotus.Test.SqliteRepo.query!("SELECT 1 as test_value")
          end,
          read_only: true
        )

      assert {:ok, %{rows: [[1]]}} = result
    end

    @tag :mysql
    test "executes MySQL transaction with read-only mode" do
      result =
        Adapter.execute_in_transaction(
          Lotus.Test.MysqlRepo,
          fn ->
            Lotus.Test.MysqlRepo.query!("SELECT 1 as test_value")
          end,
          read_only: true
        )

      assert {:ok, %{rows: [[1]]}} = result
    end
  end

  describe "set_statement_timeout/2" do
    @tag :postgres
    test "sets statement timeout for PostgreSQL" do
      assert :ok = Adapter.set_statement_timeout(Lotus.Test.Repo, 5000)
    end

    @tag :sqlite
    test "is a no-op for SQLite" do
      assert :ok = Adapter.set_statement_timeout(Lotus.Test.SqliteRepo, 5000)
    end

    @tag :mysql
    test "sets max_execution_time for MySQL" do
      assert :ok = Adapter.set_statement_timeout(Lotus.Test.MysqlRepo, 5000)
    end
  end

  describe "set_search_path/2" do
    @tag :postgres
    test "sets search_path for PostgreSQL" do
      assert :ok = Adapter.set_search_path(Lotus.Test.Repo, "public")
    end

    @tag :sqlite
    test "is a no-op for SQLite" do
      assert :ok = Adapter.set_search_path(Lotus.Test.SqliteRepo, "ignored")
    end

    @tag :mysql
    test "is a no-op for MySQL" do
      assert :ok = Adapter.set_search_path(Lotus.Test.MysqlRepo, "ignored")
    end

    test "handles nil search_path" do
      assert :ok = Adapter.set_search_path(Lotus.Test.Repo, nil)
    end

    test "handles non-binary search_path" do
      assert :ok = Adapter.set_search_path(Lotus.Test.Repo, 123)
    end
  end

  describe "format_error/1" do
    test "formats Postgrex syntax errors" do
      error = %Postgrex.Error{
        postgres: %{code: :syntax_error, message: "syntax error at or near \"SELCT\""}
      }

      assert Adapter.format_error(error) ==
               "SQL syntax error: syntax error at or near \"SELCT\""
    end

    test "formats Postgrex general SQL errors" do
      error = %Postgrex.Error{
        postgres: %{message: "relation \"nonexistent\" does not exist"}
      }

      assert Adapter.format_error(error) ==
               "SQL error: relation \"nonexistent\" does not exist"
    end

    test "formats Postgrex errors with message field" do
      error = %Postgrex.Error{message: "connection timeout"}
      assert Adapter.format_error(error) == "SQL error: connection timeout"
    end

    test "formats Postgrex errors with exception message" do
      error = %Postgrex.Error{}
      assert is_binary(Adapter.format_error(error))
    end

    test "formats Exqlite errors" do
      error = %Exqlite.Error{message: "no such table: users"}
      assert Adapter.format_error(error) == "SQLite Error: no such table: users"
    end

    test "formats DBConnection.EncodeError" do
      error = %DBConnection.EncodeError{message: "expected int"}
      assert Adapter.format_error(error) == "expected int"
    end

    test "formats ArgumentError" do
      error = %ArgumentError{message: "invalid argument"}
      assert Adapter.format_error(error) == "invalid argument"
    end

    test "returns binary messages as-is" do
      assert Adapter.format_error("Already formatted") == "Already formatted"
    end

    test "formats other terms with inspect" do
      assert Adapter.format_error(:some_atom) == "Database Error: :some_atom"
      assert Adapter.format_error(123) == "Database Error: 123"
      assert Adapter.format_error({:error, "test"}) == "Database Error: {:error, \"test\"}"
    end

    test "formats generic exceptions" do
      error = %RuntimeError{message: "Something went wrong"}
      assert Adapter.format_error(error) == "Something went wrong"
    end
  end

  describe "param_placeholder/4" do
    @tag :postgres
    test "returns postgres placeholders with $N" do
      assert Adapter.param_placeholder(Lotus.Test.Repo, 1, "id", :integer) == "$1::integer"
      assert Adapter.param_placeholder(Lotus.Test.Repo, 2, "id", :integer) == "$2::integer"
    end

    @tag :sqlite
    test "returns sqlite placeholders with ?" do
      assert Adapter.param_placeholder(Lotus.Test.SqliteRepo, 1, "id", :integer) == "?"
      assert Adapter.param_placeholder(Lotus.Test.SqliteRepo, 2, "id", :integer) == "?"
    end

    @tag :mysql
    test "returns mysql placeholders with ?" do
      assert Adapter.param_placeholder(Lotus.Test.MysqlRepo, 1, "id", :integer) ==
               "CAST(? AS SIGNED)"

      assert Adapter.param_placeholder(Lotus.Test.MysqlRepo, 2, "id", :integer) ==
               "CAST(? AS SIGNED)"
    end

    test "defaults to Postgres when repo is nil" do
      assert Adapter.param_placeholder(nil, 1, "id", :integer) == "$1::integer"
    end
  end
end
