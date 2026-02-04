defmodule Lotus.HelpersTest do
  use ExUnit.Case, async: true

  alias Lotus.Helpers

  describe "stringify_keys/1" do
    test "converts atom keys to strings in a flat map" do
      input = %{name: "test", value: 123}
      expected = %{"name" => "test", "value" => 123}

      assert Helpers.stringify_keys(input) == expected
    end

    test "recursively converts nested map keys" do
      input = %{outer: %{inner: "value"}}
      expected = %{"outer" => %{"inner" => "value"}}

      assert Helpers.stringify_keys(input) == expected
    end

    test "handles deeply nested structures" do
      input = %{a: %{b: %{c: %{d: "deep"}}}}
      expected = %{"a" => %{"b" => %{"c" => %{"d" => "deep"}}}}

      assert Helpers.stringify_keys(input) == expected
    end

    test "preserves string keys" do
      input = %{"already" => "string", atom_key: "value"}
      expected = %{"already" => "string", "atom_key" => "value"}

      assert Helpers.stringify_keys(input) == expected
    end

    test "handles maps inside lists" do
      input = %{items: [%{id: 1}, %{id: 2}]}
      expected = %{"items" => [%{"id" => 1}, %{"id" => 2}]}

      assert Helpers.stringify_keys(input) == expected
    end

    test "handles lists of maps" do
      input = [%{name: "first"}, %{name: "second"}]
      expected = [%{"name" => "first"}, %{"name" => "second"}]

      assert Helpers.stringify_keys(input) == expected
    end

    test "preserves non-map values in lists" do
      input = [1, "two", :three, %{key: "value"}]
      expected = [1, "two", :three, %{"key" => "value"}]

      assert Helpers.stringify_keys(input) == expected
    end

    test "returns empty map for empty map" do
      assert Helpers.stringify_keys(%{}) == %{}
    end

    test "returns empty list for empty list" do
      assert Helpers.stringify_keys([]) == []
    end

    test "returns other values unchanged" do
      assert Helpers.stringify_keys("string") == "string"
      assert Helpers.stringify_keys(123) == 123
      assert Helpers.stringify_keys(nil) == nil
      assert Helpers.stringify_keys(:atom) == :atom
    end
  end

  describe "escape_like/1" do
    test "escapes percent sign" do
      assert Helpers.escape_like("100%") == "100\\%"
      assert Helpers.escape_like("%match%") == "\\%match\\%"
    end

    test "escapes underscore" do
      assert Helpers.escape_like("user_name") == "user\\_name"
      assert Helpers.escape_like("_prefix") == "\\_prefix"
    end

    test "escapes backslash" do
      assert Helpers.escape_like("path\\to\\file") == "path\\\\to\\\\file"
    end

    test "escapes multiple special characters" do
      assert Helpers.escape_like("100%_test\\value") == "100\\%\\_test\\\\value"
    end

    test "returns empty string for empty input" do
      assert Helpers.escape_like("") == ""
    end

    test "returns unchanged string when no special characters" do
      assert Helpers.escape_like("normal search term") == "normal search term"
    end

    test "handles unicode characters" do
      assert Helpers.escape_like("café_100%") == "café\\_100\\%"
    end
  end
end
