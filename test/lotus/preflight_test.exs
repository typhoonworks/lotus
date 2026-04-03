defmodule Lotus.PreflightTest do
  use Lotus.Case
  use Mimic
  alias Lotus.Preflight
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter

  @pg_adapter EctoAdapter.wrap("postgres", Lotus.Test.Repo)
  @sqlite_adapter EctoAdapter.wrap("sqlite", Lotus.Test.SqliteRepo)
  @mysql_adapter EctoAdapter.wrap("mysql", Lotus.Test.MysqlRepo)

  describe "adapter detection" do
    test "correctly identifies PostgreSQL adapter" do
      assert :ok = Preflight.authorize(@pg_adapter, "SELECT 1", [])
    end

    @tag :sqlite
    test "correctly identifies SQLite adapter" do
      assert :ok = Preflight.authorize(@sqlite_adapter, "SELECT 1", [])
    end

    @tag :mysql
    test "correctly identifies MySQL adapter" do
      assert :ok = Preflight.authorize(@mysql_adapter, "SELECT 1", [])
    end
  end

  describe "fallback behavior" do
    test "allows queries for unknown adapters" do
      unknown_adapter = %Lotus.Source.Adapter{
        name: "unknown",
        module: Lotus.Source.Adapters.Ecto,
        state: Lotus.Test.Repo,
        source_type: :other
      }

      assert :ok = Preflight.authorize(unknown_adapter, "SELECT * FROM anything", [])
    end
  end
end
