defmodule Lotus.Source.AdapterTest do
  use ExUnit.Case, async: true

  alias Lotus.Query.Statement
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
    def quote_identifier(_state, identifier), do: ~s("#{identifier}")

    @impl true
    def apply_filters(_state, %Statement{text: sql, params: params} = statement, _filters),
      do: %{statement | text: sql <> " WHERE 1=1", params: params}

    @impl true
    def apply_sorts(_state, %Statement{text: sql} = statement, _sorts),
      do: %{statement | text: sql <> " ORDER BY id"}

    @impl true
    def substitute_variable(
          _state,
          %Statement{text: sql, params: params} = statement,
          var,
          value,
          type
        ) do
      send(self(), {:mock_substitute_variable, var, value, type})
      placeholder = "<<#{var}:#{type}>>"

      {:ok,
       %{
         statement
         | text: String.replace(sql, "{{#{var}}}", placeholder),
           params: params ++ [value]
       }}
    end

    @impl true
    def substitute_list_variable(
          _state,
          %Statement{text: sql, params: params} = statement,
          var,
          values,
          type
        ) do
      send(self(), {:mock_substitute_list_variable, var, values, type})
      placeholder = "<<#{var}[]:#{type}>>"

      {:ok,
       %{
         statement
         | text: String.replace(sql, "{{#{var}}}", placeholder),
           params: params ++ values
       }}
    end

    @impl true
    def query_plan(_state, sql, _params, _opts), do: {:ok, "Seq Scan on #{sql}"}

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
    def format_error(_state, error), do: "Mock error: #{inspect(error)}"

    @impl true
    def handled_errors(_state), do: [RuntimeError]

    # --- Source Identity ---
    @impl true
    def source_type(_state), do: :postgres

    @impl true
    def supports_feature?(_state, :json), do: true
    def supports_feature?(_state, _), do: false

    @impl true
    def limit_query(_state, statement, limit), do: "#{statement} LIMIT #{limit}"

    @impl true
    def db_type_to_lotus_type(_state, "integer"), do: :integer
    def db_type_to_lotus_type(_state, _), do: :text

    @impl true
    def editor_config(_state),
      do: %{language: "sql", keywords: [], types: [], functions: [], context_boundaries: []}
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

    test "quote_identifier/2 dispatches with state", %{adapter: adapter} do
      assert ~s("users") == Adapter.quote_identifier(adapter, "users")
    end

    test "source_type/1 dispatches with state", %{adapter: adapter} do
      assert :postgres == Adapter.source_type(adapter)
    end

    test "supports_feature?/2 dispatches with state", %{adapter: adapter} do
      assert Adapter.supports_feature?(adapter, :json) == true
      assert Adapter.supports_feature?(adapter, :arrays) == false
    end

    test "health_check/1 dispatches to module with state", %{adapter: adapter} do
      assert :ok = Adapter.health_check(adapter)
    end

    test "query_plan/4 dispatches to module with state", %{adapter: adapter} do
      assert {:ok, plan} = Adapter.query_plan(adapter, "SELECT 1", [], [])
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

    test "apply_filters/3 dispatches with state", %{adapter: adapter} do
      statement = Adapter.apply_filters(adapter, Statement.new("SELECT 1"), [%{}])
      assert statement.text =~ "WHERE 1=1"
      assert statement.params == []
    end

    test "apply_sorts/3 dispatches with state", %{adapter: adapter} do
      statement = Adapter.apply_sorts(adapter, Statement.new("SELECT 1"), [:id])
      assert statement.text =~ "ORDER BY id"
    end

    test "substitute_variable/5 dispatches with state", %{adapter: adapter} do
      {:ok, statement} =
        Adapter.substitute_variable(
          adapter,
          Statement.new("SELECT * FROM t WHERE id = {{id}}"),
          "id",
          42,
          :integer
        )

      assert_received {:mock_substitute_variable, "id", 42, :integer}
      assert statement.text == "SELECT * FROM t WHERE id = <<id:integer>>"
      assert statement.params == [42]
    end

    test "substitute_list_variable/5 dispatches with state", %{adapter: adapter} do
      {:ok, statement} =
        Adapter.substitute_list_variable(
          adapter,
          Statement.new("SELECT * FROM t WHERE id IN ({{ids}})"),
          "ids",
          [1, 2, 3],
          :integer
        )

      assert_received {:mock_substitute_list_variable, "ids", [1, 2, 3], :integer}
      assert statement.text == "SELECT * FROM t WHERE id IN (<<ids[]:integer>>)"
      assert statement.params == [1, 2, 3]
    end

    test "substitute_variable/5 returns {:error, :unsupported} when callback absent" do
      stub = %Adapter{
        name: "stub",
        module: Lotus.Test.StubAdapter,
        state: nil,
        source_type: :other
      }

      assert {:error, :unsupported} =
               Adapter.substitute_variable(stub, Statement.new("x"), "v", 1, nil)
    end

    test "substitute_list_variable/5 returns {:error, :unsupported} when callback absent" do
      stub = %Adapter{
        name: "stub",
        module: Lotus.Test.StubAdapter,
        state: nil,
        source_type: :other
      }

      assert {:error, :unsupported} =
               Adapter.substitute_list_variable(stub, Statement.new("x"), "v", [1], nil)
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

    test "format_error/2 dispatches with state", %{adapter: adapter} do
      assert "Mock error: :boom" == Adapter.format_error(adapter, :boom)
    end

    test "handled_errors/1 dispatches with state", %{adapter: adapter} do
      assert [RuntimeError] = Adapter.handled_errors(adapter)
    end
  end
end
