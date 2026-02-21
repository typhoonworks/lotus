defmodule Lotus.SourcesTest do
  use Lotus.Case, async: true

  alias Lotus.Sources

  describe "resolve!/2" do
    test "resolves with string repo_opt" do
      {repo_module, repo_name} = Sources.resolve!("postgres", nil)
      assert repo_module == Lotus.Test.Repo
      assert repo_name == "postgres"
    end

    test "resolves with another string repo_opt" do
      {repo_module, repo_name} = Sources.resolve!("sqlite", nil)
      assert repo_module == Lotus.Test.SqliteRepo
      assert repo_name == "sqlite"
    end

    test "resolves with module repo_opt" do
      {repo_module, repo_name} = Sources.resolve!(Lotus.Test.Repo, nil)
      assert repo_module == Lotus.Test.Repo
      assert repo_name == "postgres"
    end

    test "resolves with different module repo_opt" do
      {repo_module, repo_name} = Sources.resolve!(Lotus.Test.SqliteRepo, nil)
      assert repo_module == Lotus.Test.SqliteRepo
      assert repo_name == "sqlite"
    end

    test "falls back to string q_repo when repo_opt is nil" do
      {repo_module, repo_name} = Sources.resolve!(nil, "mysql")
      assert repo_module == Lotus.Test.MysqlRepo
      assert repo_name == "mysql"
    end

    test "falls back to another string q_repo when repo_opt is nil" do
      {repo_module, repo_name} = Sources.resolve!(nil, "sql_server")
      assert repo_module == Lotus.Test.SQLServerRepo
      assert repo_name == "sql_server"
    end

    test "falls back to module q_repo when repo_opt is nil" do
      {repo_module, repo_name} = Sources.resolve!(nil, Lotus.Test.MysqlRepo)
      assert repo_module == Lotus.Test.MysqlRepo
      assert repo_name == "mysql"
    end

    test "falls back to another module q_repo when repo_opt is nil" do
      {repo_module, repo_name} = Sources.resolve!(nil, Lotus.Test.SQLServerRepo)
      assert repo_module == Lotus.Test.SQLServerRepo
      assert repo_name == "sql_server"
    end

    test "falls back to default repo when both are nil" do
      {repo_module, repo_name} = Sources.resolve!(nil, nil)
      assert repo_module == Lotus.Test.Repo
      assert repo_name == "postgres"
    end

    test "repo_opt takes precedence over q_repo" do
      {repo_module, repo_name} = Sources.resolve!("sqlite", "mysql")
      assert repo_module == Lotus.Test.SqliteRepo
      assert repo_name == "sqlite"
    end

    test "repo_opt module takes precedence over q_repo string" do
      {repo_module, repo_name} = Sources.resolve!(Lotus.Test.SqliteRepo, "mysql")
      assert repo_module == Lotus.Test.SqliteRepo
      assert repo_name == "sqlite"
    end

    test "raises when string repo_opt is not configured" do
      assert_raise ArgumentError, ~r/Data repo 'unknown' not configured/, fn ->
        Sources.resolve!("unknown", nil)
      end
    end

    test "raises when string q_repo is not configured and repo_opt is nil" do
      assert_raise ArgumentError, ~r/Data repo 'nonexistent' not configured/, fn ->
        Sources.resolve!(nil, "nonexistent")
      end
    end

    test "non-repo module in repo_opt falls through to q_repo" do
      {repo_module, repo_name} = Sources.resolve!(String, "sqlite")
      assert repo_module == Lotus.Test.SqliteRepo
      assert repo_name == "sqlite"
    end

    test "non-repo module in q_repo falls through to default" do
      {repo_module, repo_name} = Sources.resolve!(String, Enum)
      assert repo_module == Lotus.Test.Repo
      assert repo_name == "postgres"
    end

    test "handles invalid types gracefully" do
      {repo_module, repo_name} = Sources.resolve!(123, :atom)
      assert repo_module == Lotus.Test.Repo
      assert repo_name == "postgres"
    end
  end

  describe "name_from_module!/1" do
    test "returns configured name for a repo module" do
      assert Sources.name_from_module!(Lotus.Test.Repo) == "postgres"
      assert Sources.name_from_module!(Lotus.Test.SqliteRepo) == "sqlite"
      assert Sources.name_from_module!(Lotus.Test.MysqlRepo) == "mysql"
      assert Sources.name_from_module!(Lotus.Test.SQLServerRepo) == "sql_server"
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

    test "detects sql_server adapter from repo name" do
      assert Sources.source_type("sql_server") == :sql_server
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

    test "detects sql_server adapter from repo module" do
      assert Sources.source_type(Lotus.Test.SQLServerRepo) == :sql_server
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

    test "sql_server features" do
      assert Sources.supports_feature?(:sql_server, :search_path) == false
      assert Sources.supports_feature?(:sql_server, :make_interval) == false
      assert Sources.supports_feature?(:sql_server, :arrays) == false
      assert Sources.supports_feature?(:sql_server, :json) == false
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
      assert Sources.supports_feature?(:sql_server, :unknown_feature) == false
    end
  end
end
