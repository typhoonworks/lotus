defmodule Lotus.AdapterTest do
  use Lotus.Case, async: true

  alias Lotus.Adapter

  describe "set_read_only/1" do
    @tag :postgres
    test "sets PostgreSQL transaction to read-only" do
      assert :ok = Adapter.set_read_only(Lotus.Test.Repo)
    end

    @tag :sqlite
    test "is a no-op for SQLite" do
      assert :ok = Adapter.set_read_only(Lotus.Test.SqliteRepo)
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
        postgres: %{
          code: :syntax_error,
          message: "syntax error at or near \"SELCT\""
        }
      }

      assert Adapter.format_error(error) == "SQL syntax error: syntax error at or near \"SELCT\""
    end

    test "formats Postgrex general SQL errors" do
      error = %Postgrex.Error{
        postgres: %{
          message: "relation \"nonexistent\" does not exist"
        }
      }

      assert Adapter.format_error(error) == "SQL error: relation \"nonexistent\" does not exist"
    end

    test "formats Postgrex errors with message field" do
      error = %Postgrex.Error{
        message: "connection timeout"
      }

      assert Adapter.format_error(error) == "SQL error: connection timeout"
    end

    test "formats Postgrex errors with exception message" do
      error = %Postgrex.Error{}
      result = Adapter.format_error(error)
      assert is_binary(result)
    end

    test "formats Exqlite errors" do
      error = %Exqlite.Error{
        message: "no such table: users"
      }

      assert Adapter.format_error(error) == "SQLite Error: no such table: users"
    end

    test "formats DBConnection.EncodeError" do
      error = %DBConnection.EncodeError{
        message: "expected an integer, got \"not_a_number\""
      }

      assert Adapter.format_error(error) == "expected an integer, got \"not_a_number\""
    end

    test "formats ArgumentError" do
      error = %ArgumentError{
        message: "invalid argument"
      }

      assert Adapter.format_error(error) == "invalid argument"
    end

    test "returns binary messages as-is" do
      assert Adapter.format_error("Already formatted message") == "Already formatted message"
    end

    test "formats other errors with inspect" do
      assert Adapter.format_error(:some_atom) == "Database Error: :some_atom"
      assert Adapter.format_error(123) == "Database Error: 123"
      assert Adapter.format_error({:error, "test"}) == "Database Error: {:error, \"test\"}"
    end

    test "formats generic exceptions" do
      error = %RuntimeError{message: "Something went wrong"}
      assert Adapter.format_error(error) == "Something went wrong"
    end
  end

  describe "param_style/1" do
    test "returns :postgres for nil" do
      assert Adapter.param_style(nil) == :postgres
    end

    test "returns :postgres for PostgreSQL repo name" do
      assert Adapter.param_style("postgres") == :postgres
    end

    test "returns :sqlite for SQLite repo name" do
      assert Adapter.param_style("sqlite") == :sqlite
    end

    test "returns :postgres for PostgreSQL repo module" do
      assert Adapter.param_style(Lotus.Test.Repo) == :postgres
    end

    test "returns :sqlite for SQLite repo module" do
      assert Adapter.param_style(Lotus.Test.SqliteRepo) == :sqlite
    end

    test "raises for invalid repo name" do
      assert_raise ArgumentError, ~r/Data repo .* not configured/, fn ->
        Adapter.param_style("nonexistent_repo")
      end
    end
  end
end
