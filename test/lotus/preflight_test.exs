defmodule Lotus.PreflightTest do
  use Lotus.Case
  use Mimic
  alias Lotus.Preflight

  @pg_repo Lotus.Test.Repo
  @sqlite_repo Lotus.Test.SqliteRepo
  @mysql_repo Lotus.Test.MysqlRepo

  describe "error handling" do
    test "handles invalid repo gracefully" do
      assert {:error, msg} = Preflight.authorize(@pg_repo, "unknown_repo", "SELECT 1", [])
      assert msg == "Unknown data repo 'unknown_repo'"
    end
  end

  describe "adapter detection" do
    test "correctly identifies PostgreSQL adapter" do
      assert :ok = Preflight.authorize(@pg_repo, "postgres", "SELECT 1", [])
    end

    @tag :sqlite
    test "correctly identifies SQLite adapter" do
      assert :ok = Preflight.authorize(@sqlite_repo, "sqlite", "SELECT 1", [])
    end

    @tag :mysql
    test "correctly identifies MySQL adapter" do
      assert :ok = Preflight.authorize(@mysql_repo, "mysql", "SELECT 1", [])
    end
  end

  describe "fallback behavior" do
    test "allows queries for unknown adapters" do
      defmodule UnknownRepo do
        def __adapter__, do: Some.Unknown.Adapter
      end

      assert :ok = Preflight.authorize(UnknownRepo, "postgres", "SELECT * FROM anything", [])
    end
  end
end
