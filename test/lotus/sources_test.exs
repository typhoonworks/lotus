defmodule Lotus.SourcesTest do
  use Lotus.Case, async: true

  alias Lotus.Source.Adapter
  alias Lotus.Sources

  describe "resolve!/2" do
    test "resolves with string repo_opt" do
      adapter = Sources.resolve!("postgres", nil)
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
      assert adapter.source_type == :postgres
    end

    test "resolves with another string repo_opt" do
      adapter = Sources.resolve!("sqlite", nil)
      assert %Adapter{} = adapter
      assert adapter.name == "sqlite"
      assert adapter.state == Lotus.Test.SqliteRepo
    end

    test "resolves with module repo_opt" do
      adapter = Sources.resolve!(Lotus.Test.Repo, nil)
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "resolves with different module repo_opt" do
      adapter = Sources.resolve!(Lotus.Test.SqliteRepo, nil)
      assert %Adapter{} = adapter
      assert adapter.name == "sqlite"
      assert adapter.state == Lotus.Test.SqliteRepo
    end

    test "falls back to string q_repo when repo_opt is nil" do
      adapter = Sources.resolve!(nil, "mysql")
      assert %Adapter{} = adapter
      assert adapter.name == "mysql"
      assert adapter.state == Lotus.Test.MysqlRepo
    end

    test "falls back to module q_repo when repo_opt is nil" do
      adapter = Sources.resolve!(nil, Lotus.Test.MysqlRepo)
      assert %Adapter{} = adapter
      assert adapter.name == "mysql"
      assert adapter.state == Lotus.Test.MysqlRepo
    end

    test "falls back to default repo when both are nil" do
      adapter = Sources.resolve!(nil, nil)
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "repo_opt takes precedence over q_repo" do
      adapter = Sources.resolve!("sqlite", "mysql")
      assert %Adapter{} = adapter
      assert adapter.name == "sqlite"
      assert adapter.state == Lotus.Test.SqliteRepo
    end

    test "repo_opt module takes precedence over q_repo string" do
      adapter = Sources.resolve!(Lotus.Test.SqliteRepo, "mysql")
      assert %Adapter{} = adapter
      assert adapter.name == "sqlite"
      assert adapter.state == Lotus.Test.SqliteRepo
    end

    test "raises when string repo_opt is not configured" do
      assert_raise ArgumentError, ~r/not configured/, fn ->
        Sources.resolve!("unknown", nil)
      end
    end

    test "raises when string q_repo is not configured and repo_opt is nil" do
      assert_raise ArgumentError, ~r/not configured/, fn ->
        Sources.resolve!(nil, "nonexistent")
      end
    end

    test "non-repo module in repo_opt falls through to q_repo" do
      adapter = Sources.resolve!(String, "sqlite")
      assert %Adapter{} = adapter
      assert adapter.name == "sqlite"
      assert adapter.state == Lotus.Test.SqliteRepo
    end

    test "non-repo module in q_repo falls through to default" do
      adapter = Sources.resolve!(String, Enum)
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "handles invalid types gracefully" do
      adapter = Sources.resolve!(123, :atom)
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end
  end

  describe "name_from_module!/1" do
    test "returns configured name for a repo module" do
      assert Sources.name_from_module!(Lotus.Test.Repo) == "postgres"
      assert Sources.name_from_module!(Lotus.Test.SqliteRepo) == "sqlite"
      assert Sources.name_from_module!(Lotus.Test.MysqlRepo) == "mysql"
    end

    test "raises for unconfigured repo module" do
      defmodule UnknownRepo do
        def __adapter__, do: Ecto.Adapters.Postgres
      end

      assert_raise ArgumentError, fn ->
        Sources.name_from_module!(UnknownRepo)
      end
    end
  end

  describe "source_type/1" do
    test "detects postgres adapter from repo name" do
      assert Sources.source_type("postgres") == :postgres
    end

    test "detects sqlite adapter from repo name" do
      assert Sources.source_type("sqlite") == :sqlite
    end

    test "detects mysql adapter from repo name" do
      assert Sources.source_type("mysql") == :mysql
    end

    test "detects postgres adapter from repo module" do
      assert Sources.source_type(Lotus.Test.Repo) == :postgres
    end

    test "detects sqlite adapter from repo module" do
      assert Sources.source_type(Lotus.Test.SqliteRepo) == :sqlite
    end

    test "detects mysql adapter from repo module" do
      assert Sources.source_type(Lotus.Test.MysqlRepo) == :mysql
    end

    test "detects source type from adapter struct" do
      adapter = Sources.resolve!("postgres", nil)
      assert Sources.source_type(adapter) == :postgres
    end

    test "raises for unknown repo name" do
      assert_raise ArgumentError, ~r/Data repo 'unknown' not configured/, fn ->
        Sources.source_type("unknown")
      end
    end

    test "returns :other for unknown adapter type" do
      defmodule CustomAdapterRepo do
        def __adapter__ do
          Module.concat(["UnknownAdapter"])
        end
      end

      assert Sources.source_type(CustomAdapterRepo) == :other
    end
  end

  describe "list_sources/0" do
    test "returns all configured sources as adapters" do
      adapters = Sources.list_sources()
      names = Enum.map(adapters, & &1.name) |> Enum.sort()

      assert "mysql" in names
      assert "postgres" in names
      assert "sqlite" in names

      Enum.each(adapters, fn adapter ->
        assert %Adapter{} = adapter
      end)
    end
  end

  describe "get_source!/1" do
    test "returns adapter for configured name" do
      adapter = Sources.get_source!("postgres")
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
    end

    test "raises for unknown name" do
      assert_raise ArgumentError, ~r/Data repo 'unknown' not configured/, fn ->
        Sources.get_source!("unknown")
      end
    end
  end

  describe "default_source/0" do
    test "returns the default source as adapter" do
      adapter = Sources.default_source()
      assert %Adapter{} = adapter
      assert adapter.name == "postgres"
    end
  end

  describe "supports_feature?/2" do
    test "postgres features" do
      assert Sources.supports_feature?(:postgres, :search_path) == true
      assert Sources.supports_feature?(:postgres, :make_interval) == true
      assert Sources.supports_feature?(:postgres, :arrays) == true
      assert Sources.supports_feature?(:postgres, :json) == true
    end

    test "mysql features" do
      assert Sources.supports_feature?(:mysql, :search_path) == false
      assert Sources.supports_feature?(:mysql, :make_interval) == false
      assert Sources.supports_feature?(:mysql, :arrays) == false
      assert Sources.supports_feature?(:mysql, :json) == true
    end

    test "sqlite features" do
      assert Sources.supports_feature?(:sqlite, :search_path) == false
      assert Sources.supports_feature?(:sqlite, :make_interval) == false
      assert Sources.supports_feature?(:sqlite, :arrays) == false
      assert Sources.supports_feature?(:sqlite, :json) == true
    end

    test "unknown source type returns false for all features" do
      assert Sources.supports_feature?(:unknown, :search_path) == false
      assert Sources.supports_feature?(:unknown, :make_interval) == false
      assert Sources.supports_feature?(:unknown, :arrays) == false
      assert Sources.supports_feature?(:unknown, :json) == false
    end

    test "unknown feature returns false for all source types" do
      assert Sources.supports_feature?(:postgres, :unknown_feature) == false
      assert Sources.supports_feature?(:mysql, :unknown_feature) == false
      assert Sources.supports_feature?(:sqlite, :unknown_feature) == false
      assert Sources.supports_feature?(:other, :unknown_feature) == false
    end
  end
end
