defmodule Lotus.Storage.QueryTest do
  use Lotus.Case, async: true

  alias Lotus.Storage.Query

  describe "new/1" do
    test "builds a valid changeset with required fields" do
      attrs = %{
        name: "Recent Users",
        statement: "SELECT * FROM users WHERE active = true"
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      assert get_field(changeset, :name) == "Recent Users"
      assert get_field(changeset, :statement) == "SELECT * FROM users WHERE active = true"
    end

    test "is invalid without required fields" do
      changeset = Query.new(%{})

      refute changeset.valid?
      assert %{name: ["can't be blank"], statement: ["can't be blank"]} = errors_on(changeset)
    end

    test "is invalid when name is empty" do
      changeset = Query.new(%{name: "", statement: "SELECT 1"})

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "is invalid when statement is empty" do
      changeset = Query.new(%{name: "Test", statement: ""})

      refute changeset.valid?
      assert %{statement: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts valid search_path" do
      attrs = %{
        name: "Schema Query",
        statement: "SELECT * FROM users",
        search_path: "reporting, public"
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      assert get_field(changeset, :search_path) == "reporting, public"
    end

    test "accepts single schema in search_path" do
      changeset =
        Query.new(%{
          name: "Test",
          statement: "SELECT 1",
          search_path: "analytics"
        })

      assert changeset.valid?
      assert get_field(changeset, :search_path) == "analytics"
    end

    test "converts empty search_path to nil" do
      changeset =
        Query.new(%{
          name: "Test",
          statement: "SELECT 1",
          search_path: ""
        })

      assert changeset.valid?
      assert get_field(changeset, :search_path) == nil
    end

    test "is invalid with malformed search_path" do
      changeset =
        Query.new(%{
          name: "Test",
          statement: "SELECT 1",
          search_path: "invalid-schema, 123schema"
        })

      refute changeset.valid?

      assert %{search_path: ["must be a comma-separated list of identifiers"]} =
               errors_on(changeset)
    end

    test "is invalid when search_path is not a string" do
      changeset =
        Query.new(%{
          name: "Test",
          statement: "SELECT 1",
          search_path: 123
        })

      refute changeset.valid?
      assert %{search_path: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "update/2" do
    setup do
      {:ok, query: %Query{name: "Original", statement: "SELECT 1"}}
    end

    test "updates fields", %{query: query} do
      changeset = Query.update(query, %{name: "Updated"})

      assert changeset.valid?
      assert get_field(changeset, :name) == "Updated"
    end

    test "validates updated query statement", %{query: query} do
      changeset = Query.update(query, %{statement: ""})

      refute changeset.valid?
      assert %{statement: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "to_sql_params/2" do
    test "to_sql_params with PostgreSQL adapter uses $N placeholders" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}} AND active = {{active}}",
        var_defaults: %{},
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"min_age" => 30, "active" => true})

      assert sql == "SELECT * FROM users WHERE age > $1 AND active = $2"
      assert params == [30, true]
    end

    test "to_sql_params with SQLite adapter uses ? placeholders" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}} AND active = {{active}}",
        var_defaults: %{},
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{"min_age" => 30, "active" => true})

      assert sql == "SELECT * FROM users WHERE age > ? AND active = ?"
      assert params == [30, true]
    end

    test "to_sql_params with nil data_repo defaults to PostgreSQL style" do
      q = %Query{
        statement: "SELECT * FROM users WHERE id = {{id}}",
        var_defaults: %{},
        data_repo: nil
      }

      {sql, params} = Query.to_sql_params(q, %{"id" => 123})

      assert sql == "SELECT * FROM users WHERE id = $1"
      assert params == [123]
    end

    test "uses var_defaults when vars are not provided (PostgreSQL)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        var_defaults: %{"min_age" => 40},
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE age > $1"
      assert params == [40]
    end

    test "uses var_defaults when vars are not provided (SQLite)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        var_defaults: %{"min_age" => 40},
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE age > ?"
      assert params == [40]
    end

    test "raises if required var missing and no default" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        var_defaults: %{}
      }

      assert_raise ArgumentError, ~r/Missing required variable: min_age/, fn ->
        Query.to_sql_params(q, %{})
      end
    end

    test "handles table names as parameters (PostgreSQL)" do
      q = %Query{
        statement: "SELECT * FROM {{table}}",
        var_defaults: %{"table" => "test_users"},
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})
      assert sql == "SELECT * FROM $1"
      assert params == ["test_users"]
    end

    test "handles table names as parameters (SQLite)" do
      q = %Query{
        statement: "SELECT * FROM {{table}}",
        var_defaults: %{"table" => "test_users"},
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{})
      assert sql == "SELECT * FROM ?"
      assert params == ["test_users"]
    end

    test "ignores unused defaults" do
      q = %Query{
        statement: "SELECT * FROM users",
        var_defaults: %{"unused" => "value"}
      }

      {sql, params} = Query.to_sql_params(q, %{})
      assert sql == "SELECT * FROM users"
      assert params == []
    end

    test "handles multiple occurrences of the same var (PostgreSQL)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE name = {{name}} OR nickname = {{name}}",
        var_defaults: %{"name" => "Jack"},
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE name = $1 OR nickname = $2"
      assert params == ["Jack", "Jack"]
    end

    test "handles multiple occurrences of the same var (SQLite)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE name = {{name}} OR nickname = {{name}}",
        var_defaults: %{"name" => "Jack"},
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE name = ? OR nickname = ?"
      assert params == ["Jack", "Jack"]
    end

    test "handles complex query with multiple vars (PostgreSQL)" do
      q = %Query{
        statement:
          "SELECT * FROM {{table}} WHERE age BETWEEN {{min}} AND {{max}} AND status = {{status}}",
        var_defaults: %{"table" => "users", "status" => "active"},
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"min" => 18, "max" => 65})

      assert sql == "SELECT * FROM $1 WHERE age BETWEEN $2 AND $3 AND status = $4"
      assert params == ["users", 18, 65, "active"]
    end

    test "handles complex query with multiple vars (SQLite)" do
      q = %Query{
        statement:
          "SELECT * FROM {{table}} WHERE age BETWEEN {{min}} AND {{max}} AND status = {{status}}",
        var_defaults: %{"table" => "users", "status" => "active"},
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{"min" => 18, "max" => 65})

      assert sql == "SELECT * FROM ? WHERE age BETWEEN ? AND ? AND status = ?"
      assert params == ["users", 18, 65, "active"]
    end

    test "overrides defaults with provided vars" do
      q = %Query{
        statement: "SELECT * FROM users WHERE status = {{status}}",
        var_defaults: %{"status" => "inactive"},
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"status" => "active"})

      assert sql == "SELECT * FROM users WHERE status = $1"
      assert params == ["active"]
    end

    test "handles empty string values" do
      q = %Query{
        statement: "SELECT * FROM users WHERE name = {{name}}",
        var_defaults: %{},
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{"name" => ""})

      assert sql == "SELECT * FROM users WHERE name = ?"
      assert params == [""]
    end

    test "raises when nil value is provided" do
      q = %Query{
        statement: "SELECT * FROM users WHERE deleted_at IS {{deleted}}",
        var_defaults: %{},
        data_repo: "postgres"
      }

      assert_raise ArgumentError, ~r/Missing required variable: deleted/, fn ->
        Query.to_sql_params(q, %{"deleted" => nil})
      end
    end

    test "preserves var order in params list" do
      q = %Query{
        statement: "INSERT INTO users (name, age, email) VALUES ({{name}}, {{age}}, {{email}})",
        var_defaults: %{},
        data_repo: "postgres"
      }

      {sql, params} =
        Query.to_sql_params(q, %{"name" => "John", "age" => 30, "email" => "john@example.com"})

      assert sql == "INSERT INTO users (name, age, email) VALUES ($1, $2, $3)"
      assert params == ["John", 30, "john@example.com"]
    end
  end
end
