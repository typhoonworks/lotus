defmodule Lotus.Export.ValueMySQLTest do
  use ExUnit.Case, async: true

  alias Lotus.Export.Value

  describe "MySQL-specific types" do
    test "handles BIT fields as bitstrings" do
      # 5-bit value representing 13 (binary: 01101)
      bitstring = <<13::5>>
      assert Value.to_csv_string(bitstring) == "13"
      assert Value.for_json(bitstring) == "13"
    end

    test "handles larger BIT fields" do
      # 12-bit value
      bitstring = <<2047::12>>
      assert Value.to_csv_string(bitstring) == "2047"
      assert Value.for_json(bitstring) == "2047"
    end

    test "handles single bit" do
      # Single bit set to 1
      bitstring = <<1::1>>
      assert Value.to_csv_string(bitstring) == "1"

      # Single bit set to 0
      bitstring = <<0::1>>
      assert Value.to_csv_string(bitstring) == "0"
    end

    # MySQL returns these as regular strings/nils usually, but documenting expected behavior
    test "handles MySQL zero dates as strings" do
      # MyXQL typically returns "0000-00-00" as nil or as a string
      zero_date = "0000-00-00"
      assert Value.to_csv_string(zero_date) == "0000-00-00"
      assert Value.for_json(zero_date) == "0000-00-00"
    end

    test "handles MySQL datetime with microseconds" do
      dt = ~N[2024-01-15 10:30:45.123456]
      assert Value.to_csv_string(dt) == "2024-01-15T10:30:45.123456"
      assert Value.for_json(dt) == "2024-01-15T10:30:45.123456"
    end

    test "handles MySQL TIME as Time struct" do
      time = ~T[23:59:59.999999]
      result = Value.to_csv_string(time)
      assert result =~ "23:59:59.999999"
    end

    test "handles MySQL YEAR as integer" do
      year = 2024
      assert Value.to_csv_string(year) == "2024"
      assert Value.for_json(year) == 2024
    end

    test "handles MySQL JSON columns" do
      # MySQL JSON columns are decoded to Elixir maps/lists
      json_data = %{"name" => "test", "tags" => ["a", "b", "c"]}
      csv_result = Value.to_csv_string(json_data)
      assert csv_result =~ "name"
      assert csv_result =~ "test"
      assert csv_result =~ "tags"
      assert Value.for_json(json_data) == json_data
    end

    test "handles MySQL SET type as string" do
      set_value = "option1,option2,option3"
      assert Value.to_csv_string(set_value) == "option1,option2,option3"
      assert Value.for_json(set_value) == "option1,option2,option3"
    end

    test "handles MySQL ENUM type as string" do
      enum_value = "active"
      assert Value.to_csv_string(enum_value) == "active"
      assert Value.for_json(enum_value) == "active"
    end

    test "handles MySQL DECIMAL as Decimal struct" do
      decimal = Decimal.new("99999999.99")
      assert Value.to_csv_string(decimal) == "99999999.99"
      assert Value.for_json(decimal) == "99999999.99"
    end

    test "handles MySQL BLOB as binary" do
      # Small binary data that's not valid UTF-8
      blob = <<0xFF, 0xFE, 0xFD, 0xFC>>
      result = Value.to_csv_string(blob)
      assert result == Base.encode64(blob)
      assert Value.for_json(blob) == Base.encode64(blob)
    end

    test "handles MySQL TEXT with UTF-8" do
      # MySQL TEXT with various UTF-8 characters
      text = "Hello 世界 🌍 مرحبا"
      assert Value.to_csv_string(text) == text
      assert Value.for_json(text) == text
    end
  end

  if Code.ensure_loaded?(MyXQL.Geometry) do
    describe "MySQL Geometry types" do
      test "handles MySQL Geometry as Base64" do
        # Mock WKB data for a point
        wkb = <<0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x3F>>
        geometry = %MyXQL.Geometry{wkb: wkb, srid: 4326}
        result = Value.to_csv_string(geometry)
        assert result == Base.encode64(wkb)
      end

      test "handles MySQL Geometry with nil WKB" do
        geometry = %MyXQL.Geometry{wkb: nil, srid: 0}
        result = Value.to_csv_string(geometry)
        assert result == ""
      end
    end
  end
end
