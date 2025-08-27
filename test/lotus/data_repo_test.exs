defmodule Lotus.DataRepoTest do
  use Lotus.Case, async: true

  describe "data repository configuration" do
    test "lists configured data repositories" do
      repo_names = Lotus.list_data_repo_names()
      assert "postgres" in repo_names
      assert "sqlite" in repo_names
      assert "mysql" in repo_names
    end

    test "gets data repository by name" do
      assert Lotus.get_data_repo!("postgres") == Lotus.Test.Repo
      assert Lotus.get_data_repo!("sqlite") == Lotus.Test.SqliteRepo
      assert Lotus.get_data_repo!("mysql") == Lotus.Test.MysqlRepo
    end

    test "raises when getting non-existent data repo" do
      assert_raise ArgumentError, ~r/Data repo 'nonexistent' not configured/, fn ->
        Lotus.get_data_repo!("nonexistent")
      end
    end

    test "returns all configured data repos" do
      data_repos = Lotus.data_repos()
      assert data_repos["postgres"] == Lotus.Test.Repo
      assert data_repos["sqlite"] == Lotus.Test.SqliteRepo
      assert data_repos["mysql"] == Lotus.Test.MysqlRepo
    end
  end

  describe "query execution against different repos" do
    test "executes SQL against postgres repo by name" do
      {:ok, result} = Lotus.run_sql("SELECT 1 as test_value", [], repo: "postgres")
      assert result.columns == ["test_value"]
      assert result.rows == [[1]]
    end

    @tag :sqlite
    test "executes SQL against sqlite repo by name" do
      {:ok, result} = Lotus.run_sql("SELECT 1 as test_value", [], repo: "sqlite")
      assert result.columns == ["test_value"]
      assert result.rows == [[1]]
    end

    @tag :mysql
    test "executes SQL against mysql repo by name" do
      {:ok, result} = Lotus.run_sql("SELECT 1 as test_value", [], repo: "mysql")
      assert result.columns == ["test_value"]
      assert result.rows == [[1]]
    end

    test "executes SQL against repo module directly" do
      {:ok, result} = Lotus.run_sql("SELECT 2 as test_value", [], repo: Lotus.Test.Repo)
      assert result.columns == ["test_value"]
      assert result.rows == [[2]]
    end

    test "defaults to first configured data repo when no repo specified" do
      # Should use "postgres" since it's first in alphabetical order
      {:ok, result} = Lotus.run_sql("SELECT 3 as test_value")
      assert result.columns == ["test_value"]
      assert result.rows == [[3]]
    end
  end
end
