defmodule Lotus.Storage.QueryVariableTest do
  use Lotus.Case, async: true

  alias Lotus.Storage.QueryVariable

  describe "get_option_source/1" do
    test "return :query when it has an options_query" do
      var = build_var(options_query: "SELECT id, name FROM users ORDER BY name")
      assert :query == QueryVariable.get_option_source(var)
    end

    test "returns :static when static_options non-empty" do
      var = build_var(static_options: ~w(one two))
      assert :static == QueryVariable.get_option_source(var)
    end

    test "returns :static when neither query nor static options" do
      var = build_var()
      assert :static == QueryVariable.get_option_source(var)
    end

    test "treats blank options_query as static" do
      var = build_var(options_query: "   ")
      assert :static == QueryVariable.get_option_source(var)
    end
  end

  def build_var(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "var",
        type: :text,
        widget: :input,
        label: "Var",
        default: nil,
        static_options: [],
        options_query: nil
      })

    struct(QueryVariable, attrs)
  end
end
