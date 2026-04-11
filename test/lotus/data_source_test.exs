defmodule Lotus.DataSourceTest do
  use Lotus.Case, async: true

  describe "data source configuration" do
    test "lists configured data sources" do
      source_names = Lotus.list_data_source_names()
      assert "postgres" in source_names
      assert "sqlite" in source_names
      assert "mysql" in source_names
    end

    test "gets data source by name" do
      assert Lotus.get_data_source!("postgres") == Lotus.Test.Repo
      assert Lotus.get_data_source!("sqlite") == Lotus.Test.SqliteRepo
      assert Lotus.get_data_source!("mysql") == Lotus.Test.MysqlRepo
    end

    test "raises when getting non-existent data source" do
      assert_raise ArgumentError, ~r/Data source 'nonexistent' not configured/, fn ->
        Lotus.get_data_source!("nonexistent")
      end
    end

    test "returns all configured data sources" do
      data_sources = Lotus.data_sources()
      assert data_sources["postgres"] == Lotus.Test.Repo
      assert data_sources["sqlite"] == Lotus.Test.SqliteRepo
      assert data_sources["mysql"] == Lotus.Test.MysqlRepo
    end
  end

  describe "query execution against different repos" do
    test "executes SQL against postgres repo by name" do
      {:ok, result} = Lotus.run_statement("SELECT 1 as test_value", [], repo: "postgres")
      assert result.columns == ["test_value"]
      assert result.rows == [[1]]
    end

    @tag :sqlite
    test "executes SQL against sqlite repo by name" do
      {:ok, result} = Lotus.run_statement("SELECT 1 as test_value", [], repo: "sqlite")
      assert result.columns == ["test_value"]
      assert result.rows == [[1]]
    end

    @tag :mysql
    test "executes SQL against mysql repo by name" do
      {:ok, result} = Lotus.run_statement("SELECT 1 as test_value", [], repo: "mysql")
      assert result.columns == ["test_value"]
      assert result.rows == [[1]]
    end

    test "executes SQL against repo module directly" do
      {:ok, result} = Lotus.run_statement("SELECT 2 as test_value", [], repo: Lotus.Test.Repo)
      assert result.columns == ["test_value"]
      assert result.rows == [[2]]
    end

    test "defaults to first configured data source when no repo specified" do
      # Should use "postgres" since it's first in alphabetical order
      {:ok, result} = Lotus.run_statement("SELECT 3 as test_value")
      assert result.columns == ["test_value"]
      assert result.rows == [[3]]
    end
  end
end
