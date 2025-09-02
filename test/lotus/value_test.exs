defmodule Lotus.ValueTest do
  use ExUnit.Case, async: true

  alias Lotus.Value

  describe "for_json/1" do
    test "delegates to Export.Value.for_json/1" do
      date = ~D[2024-01-15]
      assert Value.for_json(date) == "2024-01-15"

      assert Value.for_json(nil) == nil
      assert Value.for_json(42) == 42
      assert Value.for_json("test") == "test"
    end
  end

  describe "to_csv_string/1" do
    test "delegates to Export.Value.to_csv_string/1" do
      date = ~D[2024-01-15]
      assert Value.to_csv_string(date) == "2024-01-15"

      assert Value.to_csv_string(nil) == ""
      assert Value.to_csv_string(42) == "42"
      assert Value.to_csv_string(true) == "true"
    end
  end

  describe "to_display_string/1" do
    test "delegates to Export.Value.to_display_string/1" do
      date = ~D[2024-01-15]
      assert Value.to_display_string(date) == "2024-01-15"

      assert Value.to_display_string(nil) == ""
      assert Value.to_display_string(42) == "42"
      assert Value.to_display_string(true) == "true"
    end

    test "handles various data types" do
      dt = ~U[2024-01-15 10:30:00Z]
      assert Value.to_display_string(dt) == "2024-01-15T10:30:00Z"

      ndt = ~N[2024-01-15 10:30:00]
      assert Value.to_display_string(ndt) == "2024-01-15T10:30:00"

      time = ~T[10:30:00]
      assert Value.to_display_string(time) == "10:30:00"
    end
  end
end
