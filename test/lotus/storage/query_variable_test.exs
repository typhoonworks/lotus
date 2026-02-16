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

    test "returns :static when static_options has tuples" do
      var = build_var(static_options: [{"val1", "Label 1"}, {"val2", "Label 2"}])
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

  describe "changeset/2 with tuple static_options" do
    test "accepts tuple format for static_options" do
      attrs = %{
        name: "status",
        type: :text,
        widget: :select,
        static_options: [{"active", "Active"}, {"inactive", "Inactive"}]
      }

      changeset = QueryVariable.changeset(%QueryVariable{}, attrs)
      assert changeset.valid?

      variable = Ecto.Changeset.apply_changes(changeset)

      assert [
               %{value: "active", label: "Active"},
               %{value: "inactive", label: "Inactive"}
             ] = variable.static_options
    end

    test "rejects mixed format for static_options" do
      attrs = %{
        name: "priority",
        type: :text,
        widget: :select,
        static_options: ["low", {"medium", "Medium Priority"}, "high"]
      }

      changeset = QueryVariable.changeset(%QueryVariable{}, attrs)
      refute changeset.valid?

      assert %{static_options: [error_msg]} = errors_on(changeset)
      assert error_msg =~ "cannot mix different formats"
    end

    test "accepts all-string format for static_options" do
      attrs = %{
        name: "priority",
        type: :text,
        widget: :select,
        static_options: ["low", "medium", "high"]
      }

      changeset = QueryVariable.changeset(%QueryVariable{}, attrs)
      assert changeset.valid?

      variable = Ecto.Changeset.apply_changes(changeset)

      assert [
               %{value: "low", label: "low"},
               %{value: "medium", label: "medium"},
               %{value: "high", label: "high"}
             ] = variable.static_options
    end
  end

  describe "list field" do
    test "defaults to false" do
      attrs = %{name: "test", type: :text}
      changeset = QueryVariable.changeset(%QueryVariable{}, attrs)
      assert changeset.valid?

      variable = Ecto.Changeset.apply_changes(changeset)
      assert variable.list == false
    end

    test "list: true persists through changeset" do
      attrs = %{name: "countries", type: :text, list: true}
      changeset = QueryVariable.changeset(%QueryVariable{}, attrs)
      assert changeset.valid?

      variable = Ecto.Changeset.apply_changes(changeset)
      assert variable.list == true
    end

    test "list: false persists through changeset" do
      attrs = %{name: "status", type: :text, list: false}
      changeset = QueryVariable.changeset(%QueryVariable{}, attrs)
      assert changeset.valid?

      variable = Ecto.Changeset.apply_changes(changeset)
      assert variable.list == false
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
