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
    test "allows queries when adapter returns :skip" do
      unknown_adapter = %Lotus.Source.Adapter{
        name: "unknown",
        module: Lotus.Test.NoOpAdapter,
        state: nil,
        source_type: :other
      }

      assert :ok = Preflight.authorize(unknown_adapter, "SELECT * FROM anything", [])
    end

    test "allows queries when adapter does not implement extract_accessed_resources" do
      stub_adapter = %Lotus.Source.Adapter{
        name: "stub",
        module: Lotus.Test.StubAdapter,
        state: nil,
        source_type: :other
      }

      assert :ok = Preflight.authorize(stub_adapter, "SELECT * FROM anything", [])
    end
  end
end
