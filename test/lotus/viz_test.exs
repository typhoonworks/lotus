defmodule Lotus.VizTest do
  use Lotus.Case, async: true

  import Lotus.Fixtures

  alias Lotus.{Result, Storage, Viz}
  alias Lotus.Storage.QueryVisualization

  describe "create_visualization/2" do
    test "creates visualization with valid attributes" do
      query = query_fixture(%{name: "Sales by Month", statement: "SELECT 1 as x"})

      cfg = %{
        "chart" => "line",
        "x" => %{"field" => "created_at", "kind" => "temporal", "timeUnit" => "month"},
        "y" => [%{"field" => "revenue", "agg" => "sum"}],
        "series" => %{"field" => "region"},
        "filters" => [%{"field" => "region", "op" => "=", "value" => "EMEA"}],
        "options" => %{"legend" => true, "stack" => "none"}
      }

      assert {:ok, %QueryVisualization{} = viz} =
               Viz.create_visualization(query, %{name: "Main", position: 0, config: cfg})

      assert viz.name == "Main"
      assert viz.position == 0
      assert viz.config == cfg
    end

    test "associates visualization with query" do
      query = query_fixture()
      cfg = %{"chart" => "table"}

      assert {:ok, viz} =
               Viz.create_visualization(query, %{name: "Test", position: 0, config: cfg})

      assert viz.query_id == query.id
    end

    test "sets version to 1 on creation" do
      query = query_fixture()
      cfg = %{"chart" => "table"}

      assert {:ok, viz} =
               Viz.create_visualization(query, %{name: "Test", position: 0, config: cfg})

      assert viz.version == 1
    end

    test "enforces unique name within a query" do
      query = query_fixture(%{name: "Users", statement: "SELECT 1"})
      cfg = %{"chart" => "table"}

      assert {:ok, _} = Viz.create_visualization(query, %{name: "A", position: 0, config: cfg})

      assert {:error, cs} =
               Viz.create_visualization(query, %{name: "A", position: 1, config: cfg})

      assert %{name: ["name must be unique within the query"]} = errors_on(cs)
    end

    test "allows same name on different queries" do
      query1 = query_fixture(%{name: "Users", statement: "SELECT 1"})
      query2 = query_fixture(%{name: "Posts", statement: "SELECT 1"})
      cfg = %{"chart" => "table"}

      assert {:ok, _} = Viz.create_visualization(query1, %{name: "A", position: 0, config: cfg})
      assert {:ok, _} = Viz.create_visualization(query2, %{name: "A", position: 0, config: cfg})
    end
  end

  describe "update_visualization/2" do
    test "updates visualization with valid attributes" do
      query = query_fixture()
      viz = visualization_fixture(query, %{name: "Original", position: 0})

      assert {:ok, updated} = Viz.update_visualization(viz, %{name: "Updated", position: 1})
      assert updated.name == "Updated"
      assert updated.position == 1
    end

    test "updates name" do
      query = query_fixture()
      viz = visualization_fixture(query, %{name: "Original"})

      assert {:ok, updated} = Viz.update_visualization(viz, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "updates position" do
      query = query_fixture()
      viz = visualization_fixture(query, %{position: 0})

      assert {:ok, updated} = Viz.update_visualization(viz, %{position: 5})
      assert updated.position == 5
    end

    test "returns error when updating to duplicate name" do
      query = query_fixture()
      _viz1 = visualization_fixture(query, %{name: "First"})
      viz2 = visualization_fixture(query, %{name: "Second"})

      assert {:error, cs} = Viz.update_visualization(viz2, %{name: "First"})
      assert %{name: ["name must be unique within the query"]} = errors_on(cs)
    end
  end

  describe "list_visualizations/1" do
    test "returns empty list when no visualizations exist" do
      query = query_fixture()
      assert [] == Viz.list_visualizations(query.id)
    end

    test "returns visualizations ordered by position then id" do
      query = query_fixture()
      cfg = %{"chart" => "table"}

      {:ok, v1} = Viz.create_visualization(query, %{name: "First", position: 2, config: cfg})
      {:ok, v2} = Viz.create_visualization(query, %{name: "Second", position: 0, config: cfg})
      {:ok, v3} = Viz.create_visualization(query, %{name: "Third", position: 0, config: cfg})

      result = Viz.list_visualizations(query.id)

      # Position 0 items first (ordered by id), then position 2
      assert [%{name: "Second"}, %{name: "Third"}, %{name: "First"}] = result
      assert Enum.at(result, 0).id == v2.id
      assert Enum.at(result, 1).id == v3.id
      assert Enum.at(result, 2).id == v1.id
    end

    test "accepts Query struct as argument" do
      query = query_fixture()
      cfg = %{"chart" => "table"}
      {:ok, _} = Viz.create_visualization(query, %{name: "Viz", position: 0, config: cfg})

      assert [%{name: "Viz"}] = Viz.list_visualizations(query)
    end
  end

  describe "delete_visualization/1" do
    test "deletes by id" do
      query = query_fixture()
      viz = visualization_fixture(query, %{name: "ToDelete"})

      assert {:ok, _} = Viz.delete_visualization(viz.id)
      assert [] == Viz.list_visualizations(query.id)
    end

    test "returns error when id not found" do
      assert {:error, :not_found} = Viz.delete_visualization(999_999)
    end

    test "cascade deletes when parent query is deleted" do
      query = query_fixture()
      visualization_fixture(query, %{name: "Viz1"})
      visualization_fixture(query, %{name: "Viz2"})

      assert [_, _] = Viz.list_visualizations(query.id)

      # Delete the parent query
      {:ok, _} = Storage.delete_query(query)

      # Visualizations should be cascade deleted
      assert [] == Viz.list_visualizations(query.id)
    end
  end

  describe "changeset validation" do
    test "requires name, position, config, and chart type" do
      query = query_fixture()

      assert {:error, cs} = Viz.create_visualization(query, %{})

      errors = errors_on(cs)
      assert "can't be blank" in errors[:name]
      assert "can't be blank" in errors[:position]
      assert "can't be blank" in errors[:config]
    end

    test "requires chart type in config" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"x" => %{"field" => "col1", "kind" => "temporal"}}
               })

      assert %{config: ["chart is required"]} = errors_on(cs)
    end

    test "validates name length (min 1, max 255)" do
      query = query_fixture()
      cfg = %{"chart" => "table"}

      # Empty name - validate_required fires first with "can't be blank"
      assert {:error, cs} = Viz.create_visualization(query, %{name: "", position: 0, config: cfg})
      assert %{name: [msg]} = errors_on(cs)
      assert msg =~ "blank" or msg =~ "at least"

      # Name too long
      long_name = String.duplicate("a", 256)

      assert {:error, cs} =
               Viz.create_visualization(query, %{name: long_name, position: 0, config: cfg})

      assert %{name: [msg]} = errors_on(cs)
      assert msg =~ "at most"
    end

    test "validates position must be >= 0" do
      query = query_fixture()
      cfg = %{"chart" => "table"}

      assert {:error, cs} =
               Viz.create_visualization(query, %{name: "Test", position: -1, config: cfg})

      assert %{position: [msg]} = errors_on(cs)
      assert msg =~ "greater than or equal to"
    end

    test "validates chart type must be valid" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"chart" => "invalid_type"}
               })

      assert %{config: ["invalid chart type"]} = errors_on(cs)
    end

    test "accepts all valid chart types" do
      query = query_fixture()

      valid_types = ["line", "bar", "area", "scatter", "table", "number", "heatmap"]

      for chart_type <- valid_types do
        assert {:ok, _} =
                 Viz.create_visualization(query, %{
                   name: "Chart #{chart_type}",
                   position: 0,
                   config: %{"chart" => chart_type}
                 })
      end
    end

    test "validates x.kind must be temporal|quantitative|nominal" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{
                   "chart" => "line",
                   "x" => %{"field" => "col1", "kind" => "invalid"}
                 }
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "x.kind must be"
    end

    test "validates x.field is required when x is present" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{
                   "chart" => "line",
                   "x" => %{"kind" => "temporal"}
                 }
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "x.field"
    end

    test "validates y items must be objects with field" do
      query = query_fixture()

      # y item not an object
      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"chart" => "bar", "y" => ["invalid"]}
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "y[0]"

      # y item missing field
      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"chart" => "bar", "y" => [%{"agg" => "sum"}]}
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "y[0]"
    end

    test "validates y.agg must be sum|avg|count" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{
                   "chart" => "bar",
                   "y" => [%{"field" => "col1", "agg" => "invalid"}]
                 }
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "y[0]" and msg =~ "invalid value"
    end

    test "validates series.field is required when series is present" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"chart" => "line", "series" => %{}}
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "series.field"
    end

    test "validates filter.op must be valid operator" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{
                   "chart" => "bar",
                   "filters" => [%{"field" => "col1", "op" => "invalid", "value" => 1}]
                 }
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "filters[0].op invalid"
    end

    test "validates filter.value is required" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{
                   "chart" => "bar",
                   "filters" => [%{"field" => "col1", "op" => "="}]
                 }
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "value"
    end

    test "accepts all valid filter operators" do
      query = query_fixture()
      valid_ops = ["=", "!=", "<", "<=", ">", ">=", "in", "not in"]

      for op <- valid_ops do
        assert {:ok, _} =
                 Viz.create_visualization(query, %{
                   name: "Filter #{op}",
                   position: 0,
                   config: %{
                     "chart" => "table",
                     "filters" => [%{"field" => "col", "op" => op, "value" => 1}]
                   }
                 })
      end
    end

    test "validates options.legend must be boolean" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"chart" => "line", "options" => %{"legend" => "yes"}}
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "options.legend"
    end

    test "validates options.stack must be none|stack|normalize" do
      query = query_fixture()

      assert {:error, cs} =
               Viz.create_visualization(query, %{
                 name: "Test",
                 position: 0,
                 config: %{"chart" => "bar", "options" => %{"stack" => "invalid"}}
               })

      assert %{config: [msg]} = errors_on(cs)
      assert msg =~ "options.stack"
    end

    test "accepts atom keys in config" do
      query = query_fixture()

      assert {:ok, _} =
               Viz.create_visualization(query, %{
                 name: "AtomKeys",
                 position: 0,
                 config: %{
                   chart: "line",
                   x: %{field: "date", kind: "temporal"},
                   y: [%{field: "value", agg: "sum"}]
                 }
               })
    end
  end

  describe "validate_against_result/2" do
    test "validates field existence and numeric aggregations" do
      result = %Result{
        columns: ["created_at", "revenue", "region"],
        rows: [
          [~U[2024-01-01 00:00:00Z], 10, "EMEA"],
          [~U[2024-02-01 00:00:00Z], 20.5, "APAC"],
          [~U[2024-03-01 00:00:00Z], nil, "NA"]
        ]
      }

      good = %{
        "chart" => "bar",
        "x" => %{"field" => "created_at", "kind" => "temporal"},
        "y" => [%{"field" => "revenue", "agg" => "sum"}]
      }

      assert :ok = Viz.validate_against_result(good, result)

      bad_field = %{"chart" => "number", "y" => [%{"field" => "missing", "agg" => "sum"}]}
      assert {:error, msg} = Viz.validate_against_result(bad_field, result)
      assert msg =~ "unknown column 'missing'"

      non_numeric_agg = %{
        "chart" => "bar",
        "y" => [%{"field" => "region", "agg" => "avg"}]
      }

      assert {:error, msg} = Viz.validate_against_result(non_numeric_agg, result)
      assert msg =~ "requires numeric field"
    end

    test "validates x.field exists in result columns" do
      result = %Result{columns: ["col1", "col2"], rows: []}

      cfg = %{
        "chart" => "line",
        "x" => %{"field" => "missing", "kind" => "temporal"}
      }

      assert {:error, msg} = Viz.validate_against_result(cfg, result)
      assert msg =~ "x.field references unknown column 'missing'"
    end

    test "validates series.field exists in result columns" do
      result = %Result{columns: ["col1", "col2"], rows: []}

      cfg = %{
        "chart" => "line",
        "series" => %{"field" => "missing"}
      }

      assert {:error, msg} = Viz.validate_against_result(cfg, result)
      assert msg =~ "series.field references unknown column 'missing'"
    end

    test "validates filter fields exist in result columns" do
      result = %Result{columns: ["col1", "col2"], rows: []}

      cfg = %{
        "chart" => "bar",
        "filters" => [%{"field" => "missing", "op" => "=", "value" => 1}]
      }

      assert {:error, msg} = Viz.validate_against_result(cfg, result)
      assert msg =~ "filters[0].field references unknown column 'missing'"
    end

    test "count aggregation is allowed on non-numeric fields" do
      result = %Result{
        columns: ["name", "category"],
        rows: [["Alice", "A"], ["Bob", "B"]]
      }

      cfg = %{
        "chart" => "bar",
        "y" => [%{"field" => "category", "agg" => "count"}]
      }

      assert :ok = Viz.validate_against_result(cfg, result)
    end

    test "handles all nil values in numeric column check" do
      result = %Result{
        columns: ["value"],
        rows: [[nil], [nil], [nil]]
      }

      cfg = %{
        "chart" => "number",
        "y" => [%{"field" => "value", "agg" => "sum"}]
      }

      # When all values are nil, numeric_column? returns true (permissive)
      assert :ok = Viz.validate_against_result(cfg, result)
    end

    test "supports atom-keyed config format" do
      result = %Result{
        columns: ["date", "value", "category"],
        rows: [[~U[2024-01-01 00:00:00Z], 100, "A"]]
      }

      cfg = %{
        chart: "line",
        x: %{field: "date", kind: "temporal"},
        y: [%{field: "value", agg: "sum"}],
        series: %{field: "category"}
      }

      assert :ok = Viz.validate_against_result(cfg, result)
    end

    test "validates multiple y fields" do
      result = %Result{
        columns: ["date", "revenue", "cost"],
        rows: [[~U[2024-01-01 00:00:00Z], 100, 50]]
      }

      # Valid: both fields exist and are numeric
      good_cfg = %{
        "chart" => "line",
        "y" => [
          %{"field" => "revenue", "agg" => "sum"},
          %{"field" => "cost", "agg" => "avg"}
        ]
      }

      assert :ok = Viz.validate_against_result(good_cfg, result)

      # Invalid: second field doesn't exist
      bad_cfg = %{
        "chart" => "line",
        "y" => [
          %{"field" => "revenue", "agg" => "sum"},
          %{"field" => "missing", "agg" => "avg"}
        ]
      }

      assert {:error, msg} = Viz.validate_against_result(bad_cfg, result)
      assert msg =~ "y[1]"
    end
  end

  describe "Lotus module delegations" do
    test "delegates list_visualizations/1" do
      query = query_fixture()
      visualization_fixture(query, %{name: "Delegated"})

      assert [%{name: "Delegated"}] = Lotus.list_visualizations(query.id)
    end

    test "delegates create_visualization/2" do
      query = query_fixture()

      assert {:ok, %QueryVisualization{name: "Created"}} =
               Lotus.create_visualization(query, %{
                 name: "Created",
                 position: 0,
                 config: %{"chart" => "table"}
               })
    end

    test "delegates update_visualization/2" do
      query = query_fixture()
      viz = visualization_fixture(query)

      assert {:ok, %QueryVisualization{name: "Updated"}} =
               Lotus.update_visualization(viz, %{name: "Updated"})
    end

    test "delegates delete_visualization/1" do
      query = query_fixture()
      viz = visualization_fixture(query)

      assert {:ok, _} = Lotus.delete_visualization(viz)
      assert [] = Lotus.list_visualizations(query.id)
    end

    test "delegates validate_visualization_config/2" do
      result = %Result{columns: ["col1"], rows: []}
      cfg = %{"chart" => "table", "y" => [%{"field" => "missing"}]}

      assert {:error, msg} = Lotus.validate_visualization_config(cfg, result)
      assert msg =~ "unknown column"
    end
  end
end
