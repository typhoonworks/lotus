defmodule Lotus.PreflightTest do
  use Lotus.Case
  use Mimic
  alias Lotus.Preflight
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter

  @pg_adapter EctoAdapter.wrap("postgres", Lotus.Test.Repo)
  @sqlite_adapter EctoAdapter.wrap("sqlite", Lotus.Test.SqliteRepo)
  @mysql_adapter EctoAdapter.wrap("mysql", Lotus.Test.MysqlRepo)

  describe "adapter detection" do
    test "correctly identifies PostgreSQL adapter" do
      assert :ok = Preflight.authorize(@pg_adapter, Statement.new("SELECT 1", []))
    end

    @tag :sqlite
    test "correctly identifies SQLite adapter" do
      assert :ok = Preflight.authorize(@sqlite_adapter, Statement.new("SELECT 1", []))
    end

    @tag :mysql
    test "correctly identifies MySQL adapter" do
      assert :ok = Preflight.authorize(@mysql_adapter, Statement.new("SELECT 1", []))
    end
  end

  describe "unrestricted adapter behavior" do
    # Phase 2A: without the `:allow_unrestricted_resources` opt-in wired up
    # (planned for Phase 2D), adapters that return `{:unrestricted, _}` or
    # simply omit the callback are blocked. Phase 2D will introduce the
    # per-source opt-in that flips this to `:ok` when the host app opts in.
    test "blocks queries when adapter returns {:unrestricted, _}" do
      unknown_adapter = %Lotus.Source.Adapter{
        name: "unknown",
        module: Lotus.Test.NoOpAdapter,
        state: nil,
        source_type: :other
      }

      assert {:error, msg} =
               Preflight.authorize(unknown_adapter, Statement.new("SELECT * FROM anything"))

      assert msg =~ "Preflight blocked"
      assert msg =~ "allow_unrestricted_resources"
    end

    test "blocks queries when adapter does not implement extract_accessed_resources" do
      stub_adapter = %Lotus.Source.Adapter{
        name: "stub",
        module: Lotus.Test.StubAdapter,
        state: nil,
        source_type: :other
      }

      assert {:error, msg} =
               Preflight.authorize(stub_adapter, Statement.new("SELECT * FROM anything"))

      assert msg =~ "Preflight blocked"
    end
  end
end
