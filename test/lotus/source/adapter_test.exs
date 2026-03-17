defmodule Lotus.Source.AdapterTest do
  use ExUnit.Case, async: true

  alias Lotus.Source.Adapter

  defmodule MockAdapter do
    @moduledoc false
    @behaviour Lotus.Source.Adapter

    # --- Query Execution ---
    @impl true
    def execute_query(state, sql, params, _opts) do
      {:ok, %{columns: ["id"], rows: [[1]], num_rows: 1, sql: sql, params: params, db: state.db}}
    end

    @impl true
    def transaction(state, fun, _opts) do
      {:ok, fun.(state)}
    end

    # --- Introspection ---
    @impl true
    def list_schemas(state) do
      {:ok, [state.db]}
    end

    @impl true
    def list_tables(_state, _schemas, _opts) do
      {:ok, [{"public", "users"}, {"public", "posts"}]}
    end

    @impl true
    def get_table_schema(_state, _schema, _table) do
      {:ok,
       [
         %{name: "id", type: "integer", nullable: false, default: nil, primary_key: true},
         %{name: "name", type: "varchar(255)", nullable: false, default: nil, primary_key: false}
       ]}
    end

    @impl true
    def resolve_table_schema(_state, _table, _schemas) do
      {:ok, "public"}
    end

    # --- SQL Generation ---
    @impl true
    def quote_identifier(identifier), do: ~s("#{identifier}")

    @impl true
    def param_placeholder(index, _var, _type), do: "$#{index}"

    @impl true
    def limit_offset_placeholders(limit_idx, offset_idx), do: {"$#{limit_idx}", "$#{offset_idx}"}

    @impl true
    def apply_filters(sql, params, _filters), do: {sql <> " WHERE 1=1", params}

    @impl true
    def apply_sorts(sql, _sorts), do: sql <> " ORDER BY id"

    @impl true
    def explain_plan(_state, sql, _params, _opts), do: {:ok, "Seq Scan on #{sql}"}

    # --- Safety & Visibility ---
    @impl true
    def builtin_denies(_state), do: [{"pg_catalog", ~r/.*/}]

    @impl true
    def builtin_schema_denies(_state), do: ["information_schema"]

    @impl true
    def default_schemas(_state), do: ["public"]

    # --- Lifecycle ---
    @impl true
    def health_check(_state), do: :ok

    @impl true
    def disconnect(_state), do: :ok

    # --- Error Handling ---
    @impl true
    def format_error(error), do: "Mock error: #{inspect(error)}"

    @impl true
    def handled_errors, do: [RuntimeError]

    # --- Source Identity ---
    @impl true
    def source_type, do: :postgres

    @impl true
    def supports_feature?(:json), do: true
    def supports_feature?(_), do: false
  end

  describe "struct creation" do
    test "creates adapter struct with all fields" do
      adapter = %Adapter{
        name: "main",
        module: MockAdapter,
        state: %{db: "test_db"},
        source_type: :postgres
      }

      assert adapter.name == "main"
      assert adapter.module == MockAdapter
      assert adapter.state == %{db: "test_db"}
      assert adapter.source_type == :postgres
    end

    test "defaults all fields to nil" do
      adapter = %Adapter{}

      assert adapter.name == nil
      assert adapter.module == nil
      assert adapter.state == nil
      assert adapter.source_type == nil
    end
  end

  describe "dispatch helpers" do
    setup do
      adapter = %Adapter{
        name: "main",
        module: MockAdapter,
        state: %{db: "test_db"},
        source_type: :postgres
      }

      {:ok, adapter: adapter}
    end

    test "execute_query/4 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, result} = Adapter.execute_query(adapter, "SELECT 1", [], [])
      assert result.columns == ["id"]
      assert result.rows == [[1]]
      assert result.db == "test_db"
    end

    test "list_schemas/1 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, ["test_db"]} = Adapter.list_schemas(adapter)
    end

    test "list_tables/3 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, tables} = Adapter.list_tables(adapter, ["public"], [])
      assert {"public", "users"} in tables
    end

    test "quote_identifier/2 dispatches without state (stateless)", %{adapter: adapter} do
      assert ~s("users") == Adapter.quote_identifier(adapter, "users")
    end

    test "source_type/1 dispatches without state (stateless)", %{adapter: adapter} do
      assert :postgres == Adapter.source_type(adapter)
    end

    test "supports_feature?/2 dispatches without state (stateless)", %{adapter: adapter} do
      assert Adapter.supports_feature?(adapter, :json) == true
      assert Adapter.supports_feature?(adapter, :arrays) == false
    end

    test "health_check/1 dispatches to module with state", %{adapter: adapter} do
      assert :ok = Adapter.health_check(adapter)
    end

    test "explain_plan/4 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, plan} = Adapter.explain_plan(adapter, "SELECT 1", [], [])
      assert plan =~ "Seq Scan"
    end

    test "get_table_schema/3 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, columns} = Adapter.get_table_schema(adapter, "public", "users")
      assert length(columns) == 2
      assert hd(columns).name == "id"
    end

    test "resolve_table_schema/3 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, "public"} = Adapter.resolve_table_schema(adapter, "users", ["public"])
    end

    test "transaction/3 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, result} = Adapter.transaction(adapter, fn _state -> :done end, [])
      assert result == :done
    end

    test "param_placeholder/4 dispatches without state", %{adapter: adapter} do
      assert "$1" == Adapter.param_placeholder(adapter, 1, "id", nil)
    end

    test "limit_offset_placeholders/3 dispatches without state", %{adapter: adapter} do
      assert {"$1", "$2"} == Adapter.limit_offset_placeholders(adapter, 1, 2)
    end

    test "apply_filters/4 dispatches without state", %{adapter: adapter} do
      {sql, params} = Adapter.apply_filters(adapter, "SELECT 1", [], [%{}])
      assert sql =~ "WHERE 1=1"
      assert params == []
    end

    test "apply_sorts/3 dispatches without state", %{adapter: adapter} do
      sql = Adapter.apply_sorts(adapter, "SELECT 1", [:id])
      assert sql =~ "ORDER BY id"
    end

    test "builtin_denies/1 dispatches with state", %{adapter: adapter} do
      denies = Adapter.builtin_denies(adapter)
      assert [{"pg_catalog", _}] = denies
    end

    test "builtin_schema_denies/1 dispatches with state", %{adapter: adapter} do
      assert ["information_schema"] = Adapter.builtin_schema_denies(adapter)
    end

    test "default_schemas/1 dispatches with state", %{adapter: adapter} do
      assert ["public"] = Adapter.default_schemas(adapter)
    end

    test "disconnect/1 dispatches with state", %{adapter: adapter} do
      assert :ok = Adapter.disconnect(adapter)
    end

    test "format_error/2 dispatches without state (stateless)", %{adapter: adapter} do
      assert "Mock error: :boom" == Adapter.format_error(adapter, :boom)
    end

    test "handled_errors/1 dispatches without state (stateless)", %{adapter: adapter} do
      assert [RuntimeError] = Adapter.handled_errors(adapter)
    end
  end
end
