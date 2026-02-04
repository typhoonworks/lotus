defmodule Lotus.Storage.TypeCasterTest do
  use Lotus.Case, async: true

  alias Lotus.Storage.TypeCaster

  @column_info %{table: "users", column: "test_column"}

  describe "cast_value/3 with :uuid type" do
    test "casts valid UUID string to binary" do
      uuid_string = "550e8400-e29b-41d4-a716-446655440000"

      assert {:ok, binary} = TypeCaster.cast_value(uuid_string, :uuid, @column_info)
      assert is_binary(binary)
      assert byte_size(binary) == 16
    end

    test "casts uppercase UUID string" do
      uuid_string = "550E8400-E29B-41D4-A716-446655440000"

      assert {:ok, binary} = TypeCaster.cast_value(uuid_string, :uuid, @column_info)
      assert is_binary(binary)
      assert byte_size(binary) == 16
    end

    test "returns error for UUID without dashes (Ecto.UUID requires dashes)" do
      uuid_string = "550e8400e29b41d4a716446655440000"

      # Ecto.UUID.cast/1 requires standard UUID format with dashes
      assert {:error, _} = TypeCaster.cast_value(uuid_string, :uuid, @column_info)
    end

    test "returns error for invalid UUID format" do
      assert {:error, message} = TypeCaster.cast_value("not-a-uuid", :uuid, @column_info)
      assert message =~ "Invalid UUID format"
      assert message =~ "'not-a-uuid'"
      assert message =~ "not a valid UUID"
    end

    test "returns error for UUID with wrong length" do
      assert {:error, _} = TypeCaster.cast_value("550e8400-e29b-41d4-a716", :uuid, @column_info)
    end

    test "returns error for empty string" do
      assert {:error, _} = TypeCaster.cast_value("", :uuid, @column_info)
    end
  end

  describe "cast_value/3 with :integer type" do
    test "casts integer string to integer" do
      assert {:ok, 42} = TypeCaster.cast_value("42", :integer, @column_info)
    end

    test "casts negative integer string" do
      assert {:ok, -100} = TypeCaster.cast_value("-100", :integer, @column_info)
    end

    test "casts integer to integer (passthrough)" do
      assert {:ok, 42} = TypeCaster.cast_value(42, :integer, @column_info)
    end

    test "casts zero" do
      assert {:ok, 0} = TypeCaster.cast_value("0", :integer, @column_info)
    end

    test "returns error for float string" do
      assert {:error, _} = TypeCaster.cast_value("3.14", :integer, @column_info)
    end

    test "returns error for non-numeric string" do
      assert {:error, message} = TypeCaster.cast_value("abc", :integer, @column_info)
      assert message =~ "Invalid integer format"
      assert message =~ "'abc'"
    end

    test "returns error for string with trailing characters" do
      assert {:error, _} = TypeCaster.cast_value("42abc", :integer, @column_info)
    end

    test "returns error for empty string" do
      assert {:error, _} = TypeCaster.cast_value("", :integer, @column_info)
    end
  end

  describe "cast_value/3 with :float type" do
    test "casts float string to float" do
      assert {:ok, 3.14} = TypeCaster.cast_value("3.14", :float, @column_info)
    end

    test "casts negative float string" do
      assert {:ok, -0.5} = TypeCaster.cast_value("-0.5", :float, @column_info)
    end

    test "casts integer string to float" do
      assert {:ok, 42.0} = TypeCaster.cast_value("42", :float, @column_info)
    end

    test "casts scientific notation" do
      assert {:ok, float} = TypeCaster.cast_value("1.5e10", :float, @column_info)
      assert float == 1.5e10
    end

    test "returns error for non-numeric string" do
      assert {:error, message} = TypeCaster.cast_value("abc", :float, @column_info)
      assert message =~ "float"
    end
  end

  describe "cast_value/3 with :decimal type" do
    test "casts decimal string to Decimal" do
      assert {:ok, decimal} = TypeCaster.cast_value("123.45", :decimal, @column_info)
      assert Decimal.equal?(decimal, Decimal.new("123.45"))
    end

    test "casts integer string to Decimal" do
      assert {:ok, decimal} = TypeCaster.cast_value("100", :decimal, @column_info)
      assert Decimal.equal?(decimal, Decimal.new("100"))
    end

    test "casts negative decimal" do
      assert {:ok, decimal} = TypeCaster.cast_value("-99.99", :decimal, @column_info)
      assert Decimal.equal?(decimal, Decimal.new("-99.99"))
    end

    test "returns error for non-numeric string" do
      assert {:error, message} = TypeCaster.cast_value("abc", :decimal, @column_info)
      assert message =~ "decimal"
    end
  end

  describe "cast_value/3 with :boolean type" do
    test "casts 'true' string to true" do
      assert {:ok, true} = TypeCaster.cast_value("true", :boolean, @column_info)
    end

    test "casts 'false' string to false" do
      assert {:ok, false} = TypeCaster.cast_value("false", :boolean, @column_info)
    end

    test "casts '1' string to true" do
      assert {:ok, true} = TypeCaster.cast_value("1", :boolean, @column_info)
    end

    test "casts '0' string to false" do
      assert {:ok, false} = TypeCaster.cast_value("0", :boolean, @column_info)
    end

    test "casts integer 1 to true" do
      assert {:ok, true} = TypeCaster.cast_value(1, :boolean, @column_info)
    end

    test "casts integer 0 to false" do
      assert {:ok, false} = TypeCaster.cast_value(0, :boolean, @column_info)
    end

    test "casts 'yes' to true" do
      assert {:ok, true} = TypeCaster.cast_value("yes", :boolean, @column_info)
    end

    test "casts 'no' to false" do
      assert {:ok, false} = TypeCaster.cast_value("no", :boolean, @column_info)
    end

    test "casts 'on' to true" do
      assert {:ok, true} = TypeCaster.cast_value("on", :boolean, @column_info)
    end

    test "casts 'off' to false" do
      assert {:ok, false} = TypeCaster.cast_value("off", :boolean, @column_info)
    end

    test "casts boolean true (passthrough)" do
      assert {:ok, true} = TypeCaster.cast_value(true, :boolean, @column_info)
    end

    test "casts boolean false (passthrough)" do
      assert {:ok, false} = TypeCaster.cast_value(false, :boolean, @column_info)
    end

    test "returns error for invalid boolean string" do
      assert {:error, message} = TypeCaster.cast_value("maybe", :boolean, @column_info)
      assert message =~ "boolean"
    end
  end

  describe "cast_value/3 with :date type" do
    test "casts ISO8601 date string" do
      assert {:ok, ~D[2024-01-15]} = TypeCaster.cast_value("2024-01-15", :date, @column_info)
    end

    test "returns error for invalid date format" do
      assert {:error, message} = TypeCaster.cast_value("01-15-2024", :date, @column_info)
      assert message =~ "date"
    end

    test "returns error for invalid date values" do
      assert {:error, _} = TypeCaster.cast_value("2024-13-45", :date, @column_info)
    end

    test "returns error for non-date string" do
      assert {:error, _} = TypeCaster.cast_value("not a date", :date, @column_info)
    end
  end

  describe "cast_value/3 with :datetime type" do
    test "casts ISO8601 datetime string" do
      assert {:ok, datetime} =
               TypeCaster.cast_value("2024-01-15T10:30:00", :datetime, @column_info)

      assert datetime == ~N[2024-01-15 10:30:00]
    end

    test "casts datetime with microseconds" do
      assert {:ok, datetime} =
               TypeCaster.cast_value("2024-01-15T10:30:00.123456", :datetime, @column_info)

      assert datetime.microsecond == {123_456, 6}
    end

    test "returns error for date-only string" do
      assert {:error, _} = TypeCaster.cast_value("2024-01-15", :datetime, @column_info)
    end

    test "returns error for invalid datetime" do
      assert {:error, message} = TypeCaster.cast_value("not a datetime", :datetime, @column_info)
      assert message =~ "datetime"
    end
  end

  describe "cast_value/3 with :json type" do
    test "passes through maps" do
      value = %{"key" => "value", "nested" => %{"a" => 1}}
      assert {:ok, ^value} = TypeCaster.cast_value(value, :json, @column_info)
    end

    test "passes through lists" do
      value = [1, 2, 3]
      assert {:ok, ^value} = TypeCaster.cast_value(value, :json, @column_info)
    end

    test "parses JSON object string" do
      assert {:ok, %{"key" => "value"}} =
               TypeCaster.cast_value(~s({"key": "value"}), :json, @column_info)
    end

    test "parses JSON array string" do
      assert {:ok, [1, 2, 3]} = TypeCaster.cast_value("[1, 2, 3]", :json, @column_info)
    end

    test "returns error for invalid JSON string" do
      assert {:error, message} = TypeCaster.cast_value("{invalid json}", :json, @column_info)
      assert message =~ "json" or message =~ "JSON"
    end
  end

  describe "cast_value/3 with :binary type" do
    test "passes through binary" do
      value = <<1, 2, 3, 4>>
      assert {:ok, ^value} = TypeCaster.cast_value(value, :binary, @column_info)
    end

    test "passes through string as binary" do
      value = "hello"
      assert {:ok, ^value} = TypeCaster.cast_value(value, :binary, @column_info)
    end

    test "returns error for non-binary" do
      assert {:error, message} = TypeCaster.cast_value(123, :binary, @column_info)
      assert message =~ "binary"
    end
  end

  describe "cast_value/3 with :text type" do
    test "converts any value to string" do
      assert {:ok, "hello"} = TypeCaster.cast_value("hello", :text, @column_info)
      assert {:ok, "123"} = TypeCaster.cast_value(123, :text, @column_info)
      assert {:ok, "true"} = TypeCaster.cast_value(true, :text, @column_info)
    end
  end

  describe "cast_value/3 with :enum type" do
    test "passes through string" do
      assert {:ok, "active"} = TypeCaster.cast_value("active", :enum, @column_info)
    end

    test "converts non-string to string" do
      assert {:ok, "123"} = TypeCaster.cast_value(123, :enum, @column_info)
    end
  end

  describe "cast_value/3 with :composite type" do
    test "passes through maps" do
      value = %{"street" => "123 Main St", "city" => "Boston"}
      assert {:ok, ^value} = TypeCaster.cast_value(value, :composite, @column_info)
    end

    test "parses JSON string to map" do
      json = "{\"street\": \"123 Main St\", \"city\": \"Boston\"}"

      assert {:ok, %{"street" => "123 Main St", "city" => "Boston"}} =
               TypeCaster.cast_value(json, :composite, @column_info)
    end

    test "returns error for invalid JSON" do
      assert {:error, message} = TypeCaster.cast_value("not json", :composite, @column_info)
      assert message =~ "composite"
    end
  end

  describe "cast_value/3 with {:array, element_type}" do
    test "casts list of integers" do
      assert {:ok, [1, 2, 3]} =
               TypeCaster.cast_value(["1", "2", "3"], {:array, :integer}, @column_info)
    end

    test "casts list of strings" do
      assert {:ok, ["a", "b", "c"]} =
               TypeCaster.cast_value(["a", "b", "c"], {:array, :text}, @column_info)
    end

    test "casts list of booleans" do
      assert {:ok, [true, false, true]} =
               TypeCaster.cast_value(["true", "false", "1"], {:array, :boolean}, @column_info)
    end

    test "parses PostgreSQL array format" do
      assert {:ok, ["1", "2", "3"]} =
               TypeCaster.cast_value("{1,2,3}", {:array, :text}, @column_info)
    end

    test "parses PostgreSQL array format with spaces" do
      assert {:ok, ["a", "b", "c"]} =
               TypeCaster.cast_value("{a, b, c}", {:array, :text}, @column_info)
    end

    test "parses JSON array format" do
      assert {:ok, [1, 2, 3]} =
               TypeCaster.cast_value("[1, 2, 3]", {:array, :integer}, @column_info)
    end

    test "returns error when element casting fails" do
      assert {:error, _} =
               TypeCaster.cast_value(["1", "not-an-int", "3"], {:array, :integer}, @column_info)
    end

    test "returns error for invalid array format" do
      assert {:error, message} =
               TypeCaster.cast_value("not an array", {:array, :integer}, @column_info)

      assert message =~ "array"
    end
  end

  describe "cast_value/3 with database type string" do
    test "maps database type to Lotus type and casts" do
      column_info = Map.put(@column_info, :source_module, Lotus.Sources.Postgres)

      assert {:ok, binary} =
               TypeCaster.cast_value(
                 "550e8400-e29b-41d4-a716-446655440000",
                 "uuid",
                 column_info
               )

      assert byte_size(binary) == 16
    end

    test "handles integer database type" do
      column_info = Map.put(@column_info, :source_module, Lotus.Sources.Postgres)
      assert {:ok, 42} = TypeCaster.cast_value("42", "integer", column_info)
    end

    test "defaults to text for unknown database type" do
      column_info = Map.put(@column_info, :source_module, Lotus.Sources.Postgres)
      assert {:ok, "hello"} = TypeCaster.cast_value("hello", "unknown_type", column_info)
    end
  end

  describe "error message formatting" do
    test "produces user-friendly error message" do
      assert {:error, message} = TypeCaster.cast_value("bad", :uuid, @column_info)
      assert message =~ "Invalid UUID format"
      assert message =~ "'bad'"
      assert message =~ "not a valid UUID"
    end

    test "includes format hint for UUID" do
      assert {:error, message} = TypeCaster.cast_value("bad", :uuid, @column_info)
      assert message =~ "8-4-4-4-12"
    end

    test "includes format hint for date" do
      assert {:error, message} = TypeCaster.cast_value("bad", :date, @column_info)
      assert message =~ "Invalid date format"
      assert message =~ "ISO8601"
    end

    test "includes format hint for boolean" do
      assert {:error, message} = TypeCaster.cast_value("bad", :boolean, @column_info)
      assert message =~ "Invalid boolean format"
      assert message =~ "true/false"
    end

    test "includes format hint for datetime" do
      assert {:error, message} = TypeCaster.cast_value("bad", :datetime, @column_info)
      assert message =~ "Invalid datetime format"
      assert message =~ "ISO8601"
    end
  end
end
