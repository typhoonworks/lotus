defmodule Lotus.AI.Actions.ExecuteSQLTest do
  use Lotus.AICase, async: true

  alias Lotus.AI.Actions.ExecuteSQL
  alias Lotus.Result

  setup do
    Mimic.copy(Lotus)
    :ok
  end

  describe "run/2" do
    test "executes SQL and returns result with metadata" do
      stub(Lotus, :run_sql, fn _sql, _params, _opts ->
        {:ok,
         Result.new(["region", "revenue"], [["US", 50_000], ["EU", 30_000]],
           num_rows: 2,
           duration_ms: 42
         )}
      end)

      assert {:ok, result} =
               ExecuteSQL.run(
                 %{
                   sql: "SELECT region, SUM(amount) as revenue FROM orders GROUP BY region",
                   data_source: "postgres",
                   label: "Revenue by region"
                 },
                 %{}
               )

      assert result.label == "Revenue by region"
      assert result.columns == ["region", "revenue"]
      assert result.rows == [["US", 50_000], ["EU", 30_000]]
      assert result.num_rows == 2
      assert result.duration_ms == 42
      assert result.truncated == false
      assert result.data_source == "postgres"
    end

    test "truncates large result sets for LLM context" do
      rows = for i <- 1..100, do: [i, "row_#{i}"]

      stub(Lotus, :run_sql, fn _sql, _params, _opts ->
        {:ok, Result.new(["id", "name"], rows, num_rows: 100)}
      end)

      assert {:ok, result} =
               ExecuteSQL.run(
                 %{sql: "SELECT * FROM big_table", data_source: "postgres", label: "Big query"},
                 %{}
               )

      assert length(result.rows) == 50
      assert result.num_rows == 100
      assert result.truncated == true
    end

    test "captures query errors without failing the action" do
      stub(Lotus, :run_sql, fn _sql, _params, _opts ->
        {:error, "relation \"missing_table\" does not exist"}
      end)

      assert {:ok, result} =
               ExecuteSQL.run(
                 %{
                   sql: "SELECT * FROM missing_table",
                   data_source: "postgres",
                   label: "Bad query"
                 },
                 %{}
               )

      assert result.label == "Bad query"
      assert result.error =~ "missing_table"
      refute Map.has_key?(result, :columns)
    end

    test "enforces read-only execution" do
      expect(Lotus, :run_sql, fn _sql, _params, opts ->
        assert opts[:read_only] == true
        {:ok, Result.new(["count"], [[42]], num_rows: 1)}
      end)

      assert {:ok, _result} =
               ExecuteSQL.run(
                 %{sql: "SELECT COUNT(*) FROM users", data_source: "postgres", label: "Count"},
                 %{}
               )
    end

    test "includes timing information" do
      stub(Lotus, :run_sql, fn _sql, _params, _opts ->
        {:ok, Result.new(["x"], [[1]], num_rows: 1)}
      end)

      assert {:ok, result} =
               ExecuteSQL.run(
                 %{sql: "SELECT 1", data_source: "postgres", label: "Ping"},
                 %{}
               )

      assert %DateTime{} = result.started_at
      assert %DateTime{} = result.completed_at
    end
  end

  describe "tool metadata" do
    test "exposes name, description, and schema" do
      assert ExecuteSQL.name() == "execute_sql"
      assert ExecuteSQL.description() =~ "Execute"
      assert Keyword.has_key?(ExecuteSQL.schema(), :sql)
      assert Keyword.has_key?(ExecuteSQL.schema(), :label)
      assert Keyword.has_key?(ExecuteSQL.schema(), :data_source)
    end
  end
end
