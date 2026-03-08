defmodule Lotus.AI.Actions.ValidateSQLTest do
  use Lotus.AICase, async: true

  alias Lotus.AI.Actions.ValidateSQL

  describe "run/2" do
    test "returns valid: true when validation succeeds" do
      expect(Lotus.SQL.Validator, :validate, fn "SELECT 1", "postgres" -> :ok end)

      assert {:ok, %{valid: true}} =
               ValidateSQL.run(%{sql: "SELECT 1", data_source: "postgres"}, %{})
    end

    test "returns valid: false with error when validation fails" do
      expect(Lotus.SQL.Validator, :validate, fn _sql, "postgres" ->
        {:error, "SQL syntax error: unexpected token"}
      end)

      assert {:ok, %{valid: false, error: error}} =
               ValidateSQL.run(
                 %{sql: "This is not SQL", data_source: "postgres"},
                 %{}
               )

      assert error =~ "syntax error"
    end
  end

  describe "tool metadata" do
    test "exposes name, description, and schema" do
      assert ValidateSQL.name() == "validate_sql"
      assert ValidateSQL.description() =~ "Validate"
      assert Keyword.has_key?(ValidateSQL.schema(), :sql)
      assert Keyword.has_key?(ValidateSQL.schema(), :data_source)
    end
  end
end
