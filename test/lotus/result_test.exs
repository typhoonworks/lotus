defmodule Lotus.ResultTest do
  use ExUnit.Case, async: true

  alias Lotus.Result

  describe "new/3" do
    test "creates result with columns and rows" do
      result = Result.new(["name", "age"], [["Alice", 30], ["Bob", 25]])

      assert result.columns == ["name", "age"]
      assert result.rows == [["Alice", 30], ["Bob", 25]]
      assert result.num_rows == 2
    end

    test "creates result with opts" do
      result =
        Result.new(["id"], [[1]], num_rows: 1, duration_ms: 42, command: "select", meta: %{x: 1})

      assert result.num_rows == 1
      assert result.duration_ms == 42
      assert result.command == "select"
      assert result.meta == %{x: 1}
    end

    test "handles nil columns and rows" do
      result = Result.new(nil, nil)

      assert result.columns == []
      assert result.rows == []
      assert result.num_rows == 0
    end

    test "preserves raw values in rows" do
      {:ok, uuid_binary} = Ecto.UUID.dump("550e8400-e29b-41d4-a716-446655440000")
      result = Result.new(["id"], [[uuid_binary]])

      assert result.rows == [[uuid_binary]]
    end
  end

  describe "to_encodable/1" do
    test "returns JSON-safe map with primitive values" do
      result = Result.new(["name", "count"], [["Alice", 42]])
      encodable = Result.to_encodable(result)

      assert encodable.columns == ["name", "count"]
      assert encodable.rows == [["Alice", 42]]
      assert encodable.num_rows == 1
    end

    test "normalizes UUID binary values to strings" do
      {:ok, uuid_binary} = Ecto.UUID.dump("550e8400-e29b-41d4-a716-446655440000")
      result = Result.new(["id", "name"], [[uuid_binary, "Alice"]])
      encodable = Result.to_encodable(result)

      assert [[id, "Alice"]] = encodable.rows
      assert id == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "normalizes Date values to ISO8601 strings" do
      result = Result.new(["created_at"], [[~D[2024-06-15]]])
      encodable = Result.to_encodable(result)

      assert encodable.rows == [["2024-06-15"]]
    end

    test "normalizes DateTime values to ISO8601 strings" do
      result = Result.new(["created_at"], [[~U[2024-06-15 10:30:00Z]]])
      encodable = Result.to_encodable(result)

      assert encodable.rows == [["2024-06-15T10:30:00Z"]]
    end

    test "normalizes NaiveDateTime values to ISO8601 strings" do
      result = Result.new(["created_at"], [[~N[2024-06-15 10:30:00]]])
      encodable = Result.to_encodable(result)

      assert encodable.rows == [["2024-06-15T10:30:00"]]
    end

    test "normalizes Decimal values to strings" do
      result = Result.new(["amount"], [[Decimal.new("123.45")]])
      encodable = Result.to_encodable(result)

      assert encodable.rows == [["123.45"]]
    end

    test "normalizes non-UTF-8 binaries to Base64" do
      binary = <<255, 254, 253, 252>>
      result = Result.new(["data"], [[binary]])
      encodable = Result.to_encodable(result)

      assert encodable.rows == [[Base.encode64(binary)]]
    end

    test "normalizes mixed database types" do
      {:ok, uuid_binary} = Ecto.UUID.dump("550e8400-e29b-41d4-a716-446655440000")

      result =
        Result.new(
          ["id", "name", "created_at", "amount", "active"],
          [[uuid_binary, "Alice", ~D[2024-06-15], Decimal.new("99.99"), true]]
        )

      encodable = Result.to_encodable(result)

      assert [["550e8400-e29b-41d4-a716-446655440000", "Alice", "2024-06-15", "99.99", true]] =
               encodable.rows
    end

    test "is JSON-encodable" do
      {:ok, uuid_binary} = Ecto.UUID.dump("550e8400-e29b-41d4-a716-446655440000")

      result =
        Result.new(
          ["id", "name", "created_at"],
          [[uuid_binary, "Alice", ~D[2024-06-15]]]
        )

      # Must not raise
      encoded = Lotus.JSON.encode!(Result.to_encodable(result))
      decoded = Lotus.JSON.decode!(encoded)

      assert [["550e8400-e29b-41d4-a716-446655440000", "Alice", "2024-06-15"]] = decoded["rows"]
    end

    test "preserves nil values" do
      result = Result.new(["name", "age"], [["Alice", nil]])
      encodable = Result.to_encodable(result)

      assert encodable.rows == [["Alice", nil]]
    end

    test "includes metadata fields" do
      result = Result.new(["id"], [[1]], duration_ms: 42, command: "select", meta: %{x: 1})
      encodable = Result.to_encodable(result)

      assert encodable.duration_ms == 42
      assert encodable.command == "select"
      assert encodable.meta == %{x: 1}
    end
  end
end
