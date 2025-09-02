defmodule Lotus.ExportTest do
  use ExUnit.Case, async: true

  alias Lotus.{Export, QueryResult}

  describe "to_csv/1" do
    test "exports result to CSV format" do
      result =
        QueryResult.new(
          ["id", "name", "age"],
          [
            [1, "Alice", 30],
            [2, "Bob", 25],
            [3, "Charlie", nil]
          ]
        )

      csv_iodata = Export.to_csv(result)
      csv_string = IO.iodata_to_binary(csv_iodata)

      expected = """
      id,name,age
      1,Alice,30
      2,Bob,25
      3,Charlie,
      """

      assert String.trim(csv_string) == String.trim(expected)
    end

    test "handles special characters in CSV" do
      result =
        QueryResult.new(
          ["name", "description"],
          [
            ["Product A", "Contains \"quotes\""],
            ["Product B", "Has, comma"],
            ["Product C", "Has\nnewline"]
          ]
        )

      csv_iodata = Export.to_csv(result)
      csv_string = IO.iodata_to_binary(csv_iodata)

      assert csv_string =~ "\"Contains \"\"quotes\"\"\""
      assert csv_string =~ "\"Has, comma\""
      assert csv_string =~ "\"Has\nnewline\""
    end

    test "handles empty result" do
      result = QueryResult.new([], [])
      csv_iodata = Export.to_csv(result)
      csv_string = IO.iodata_to_binary(csv_iodata)

      assert csv_string == "\n"
    end
  end

  describe "to_json/1" do
    test "exports result to JSON format" do
      result =
        QueryResult.new(
          ["id", "name", "active"],
          [
            [1, "Alice", true],
            [2, "Bob", false]
          ]
        )

      json_string = Export.to_json(result)
      decoded = Lotus.JSON.decode!(json_string)

      assert decoded == [
               %{"id" => 1, "name" => "Alice", "active" => true},
               %{"id" => 2, "name" => "Bob", "active" => false}
             ]
    end

    test "handles nil values in JSON" do
      result =
        QueryResult.new(
          ["id", "value"],
          [
            [1, nil],
            [2, "test"]
          ]
        )

      json_string = Export.to_json(result)
      decoded = Lotus.JSON.decode!(json_string)

      assert decoded == [
               %{"id" => 1, "value" => nil},
               %{"id" => 2, "value" => "test"}
             ]
    end

    test "handles empty result in JSON" do
      result = QueryResult.new(["col1", "col2"], [])
      json_string = Export.to_json(result)

      assert json_string == "[]"
    end
  end

  describe "to_jsonl/1" do
    test "exports result to JSONL format" do
      result =
        QueryResult.new(
          ["id", "name"],
          [
            [1, "Alice"],
            [2, "Bob"],
            [3, "Charlie"]
          ]
        )

      jsonl_string = Export.to_jsonl(result)
      lines = String.split(jsonl_string, "\n")

      assert length(lines) == 3

      assert Lotus.JSON.decode!(Enum.at(lines, 0)) == %{"id" => 1, "name" => "Alice"}
      assert Lotus.JSON.decode!(Enum.at(lines, 1)) == %{"id" => 2, "name" => "Bob"}
      assert Lotus.JSON.decode!(Enum.at(lines, 2)) == %{"id" => 3, "name" => "Charlie"}
    end

    test "handles single row in JSONL" do
      result =
        QueryResult.new(
          ["id", "name"],
          [[1, "Alice"]]
        )

      jsonl_string = Export.to_jsonl(result)

      assert jsonl_string == ~s({"id":1,"name":"Alice"})
    end

    test "handles empty result in JSONL" do
      result = QueryResult.new(["col1"], [])
      jsonl_string = Export.to_jsonl(result)

      assert jsonl_string == ""
    end
  end

  describe "date/time handling" do
    test "normalizes DateTime values" do
      dt = ~U[2024-01-15 10:30:00Z]
      result = QueryResult.new(["timestamp"], [[dt]])

      csv_iodata = Export.to_csv(result)
      csv_string = IO.iodata_to_binary(csv_iodata)

      assert csv_string =~ "2024-01-15T10:30:00Z"
    end

    test "normalizes Date values" do
      date = ~D[2024-01-15]
      result = QueryResult.new(["date"], [[date]])

      csv_iodata = Export.to_csv(result)
      csv_string = IO.iodata_to_binary(csv_iodata)

      assert csv_string =~ "2024-01-15"
    end

    test "normalizes NaiveDateTime values" do
      ndt = ~N[2024-01-15 10:30:00]
      result = QueryResult.new(["timestamp"], [[ndt]])

      csv_iodata = Export.to_csv(result)
      csv_string = IO.iodata_to_binary(csv_iodata)

      assert csv_string =~ "2024-01-15T10:30:00"
    end
  end
end
