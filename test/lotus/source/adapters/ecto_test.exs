defmodule Lotus.Source.Adapters.EctoTest do
  use Lotus.Case, async: true

  alias Lotus.Source.Adapter
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter
  alias Lotus.Test.Repo

  describe "wrap/2" do
    test "creates an Adapter struct with correct fields" do
      adapter = EctoAdapter.wrap("main", Repo)

      assert %Adapter{} = adapter
      assert adapter.name == "main"
      assert adapter.module == EctoAdapter
      assert adapter.state == Repo
      assert adapter.source_type == :postgres
    end
  end

  describe "detect_source_type/1" do
    test "detects Postgres adapter" do
      assert EctoAdapter.detect_source_type(Repo) == :postgres
    end

    test "detects SQLite adapter" do
      assert EctoAdapter.detect_source_type(Lotus.Test.SqliteRepo) == :sqlite
    end

    test "detects MySQL adapter" do
      assert EctoAdapter.detect_source_type(Lotus.Test.MysqlRepo) == :mysql
    end
  end

  describe "source_type/0" do
    test "returns the source type from the wrapped repo" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert Adapter.source_type(adapter) == :postgres
    end
  end

  describe "supports_feature?/1" do
    test "postgres supports search_path" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert Adapter.supports_feature?(adapter, :search_path)
    end

    test "postgres supports json" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert Adapter.supports_feature?(adapter, :json)
    end

    test "postgres supports arrays" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert Adapter.supports_feature?(adapter, :arrays)
    end

    test "postgres does not support unknown features" do
      adapter = EctoAdapter.wrap("main", Repo)
      refute Adapter.supports_feature?(adapter, :time_travel)
    end
  end

  describe "introspection callbacks" do
    test "list_schemas/1 returns {:ok, _} tuple" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert {:ok, schemas} = Adapter.list_schemas(adapter)
      assert is_list(schemas)
      assert "public" in schemas
    end

    test "list_tables/3 returns {:ok, _} tuple" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert {:ok, tables} = Adapter.list_tables(adapter, ["public"], include_views: false)
      assert is_list(tables)
    end

    test "get_table_schema/3 returns {:ok, _} tuple" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert {:ok, columns} = Adapter.get_table_schema(adapter, "public", "lotus_queries")
      assert is_list(columns)
    end

    test "resolve_table_schema/3 returns {:ok, _} tuple" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert {:ok, schema} = Adapter.resolve_table_schema(adapter, "lotus_queries", ["public"])
      assert schema == "public"
    end
  end

  describe "SQL generation callbacks" do
    test "quote_identifier/1 uses Postgres double-quoting" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert ~s("users") == Adapter.quote_identifier(adapter, "users")
    end

    test "param_placeholder/3 uses Postgres positional params" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert "$1" == Adapter.param_placeholder(adapter, 1, "id", nil)
    end

    test "limit_offset_placeholders/2 uses Postgres positional params" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert {"$1", "$2"} == Adapter.limit_offset_placeholders(adapter, 1, 2)
    end
  end

  describe "safety callbacks" do
    test "builtin_denies/1 returns deny rules" do
      adapter = EctoAdapter.wrap("main", Repo)
      denies = Adapter.builtin_denies(adapter)
      assert is_list(denies)
      assert {"pg_catalog", ~r/.*/} in denies
    end

    test "builtin_schema_denies/1 returns schema deny patterns" do
      adapter = EctoAdapter.wrap("main", Repo)
      denies = Adapter.builtin_schema_denies(adapter)
      assert is_list(denies)
      assert "pg_catalog" in denies
    end

    test "default_schemas/1 returns default schemas" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert ["public"] == Adapter.default_schemas(adapter)
    end
  end

  describe "lifecycle callbacks" do
    test "health_check/1 succeeds for running repo" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert :ok = Adapter.health_check(adapter)
    end

    test "disconnect/1 returns :ok (static repos managed by supervisor)" do
      adapter = EctoAdapter.wrap("main", Repo)
      assert :ok = Adapter.disconnect(adapter)
    end
  end

  describe "execute_query/4" do
    test "executes a simple query and returns result map" do
      adapter = EctoAdapter.wrap("main", Repo)

      assert {:ok, result} = Adapter.execute_query(adapter, "SELECT 1 AS num", [], [])
      assert result.columns == ["num"]
      assert result.rows == [[1]]
      assert result.num_rows == 1
    end

    test "returns error for invalid SQL" do
      adapter = EctoAdapter.wrap("main", Repo)

      assert {:error, _reason} = Adapter.execute_query(adapter, "INVALID SQL", [], [])
    end

    test "respects search_path option" do
      adapter = EctoAdapter.wrap("main", Repo)

      assert {:ok, result} =
               Adapter.execute_query(adapter, "SELECT 1 AS num", [], search_path: "public")

      assert result.columns == ["num"]
    end
  end

  describe "transaction/3" do
    test "executes a function in a transaction" do
      adapter = EctoAdapter.wrap("main", Repo)

      assert {:ok, result} =
               Adapter.transaction(
                 adapter,
                 fn repo ->
                   repo.query!("SELECT 42 AS answer")
                 end,
                 []
               )

      assert %{rows: [[42]]} = result
    end
  end

  describe "error handling" do
    test "format_error/1 formats exceptions" do
      adapter = EctoAdapter.wrap("main", Repo)
      error = %RuntimeError{message: "boom"}
      assert is_binary(Adapter.format_error(adapter, error))
    end

    test "handled_errors/0 returns list of exception modules" do
      adapter = EctoAdapter.wrap("main", Repo)
      errors = Adapter.handled_errors(adapter)
      assert is_list(errors)
      assert Postgrex.Error in errors
    end
  end
end
