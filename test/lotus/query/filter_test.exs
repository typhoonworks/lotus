defmodule Lotus.Query.FilterTest do
  use ExUnit.Case, async: true

  alias Lotus.Query.Filter

  describe "new/3" do
    test "creates a filter with column, op, and value" do
      filter = Filter.new("region", :eq, "US")
      assert %Filter{column: "region", op: :eq, value: "US"} = filter
    end

    test "creates a filter without value for nullary operators" do
      filter = Filter.new("deleted_at", :is_null)
      assert %Filter{column: "deleted_at", op: :is_null, value: nil} = filter
    end

    test "raises for invalid operator" do
      assert_raise FunctionClauseError, fn ->
        Filter.new("col", :invalid, "val")
      end
    end
  end

  describe "operators/0" do
    test "returns all valid operators" do
      ops = Filter.operators()
      assert :eq in ops
      assert :neq in ops
      assert :gt in ops
      assert :lt in ops
      assert :gte in ops
      assert :lte in ops
      assert :like in ops
      assert :is_null in ops
      assert :is_not_null in ops
    end
  end

  describe "operator_label/1" do
    test "returns display labels for operators" do
      assert Filter.operator_label(:eq) == "="
      assert Filter.operator_label(:neq) == "≠"
      assert Filter.operator_label(:gt) == ">"
      assert Filter.operator_label(:lt) == "<"
      assert Filter.operator_label(:gte) == "≥"
      assert Filter.operator_label(:lte) == "≤"
      assert Filter.operator_label(:like) == "LIKE"
      assert Filter.operator_label(:is_null) == "IS NULL"
      assert Filter.operator_label(:is_not_null) == "IS NOT NULL"
    end
  end
end
