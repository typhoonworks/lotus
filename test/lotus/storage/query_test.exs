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
        variables: [],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"min_age" => 30, "active" => true})

      assert sql == "SELECT * FROM users WHERE age > $1 AND active = $2"
      assert params == [30, true]
    end

    test "to_sql_params with SQLite adapter uses ? placeholders" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}} AND active = {{active}}",
        variables: [],
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{"min_age" => 30, "active" => true})

      assert sql == "SELECT * FROM users WHERE age > ? AND active = ?"
      assert params == [30, true]
    end

    test "to_sql_params with nil data_repo defaults to PostgreSQL style" do
      q = %Query{
        statement: "SELECT * FROM users WHERE id = {{id}}",
        variables: [],
        data_repo: nil
      }

      {sql, params} = Query.to_sql_params(q, %{"id" => 123})

      assert sql == "SELECT * FROM users WHERE id = $1"
      assert params == [123]
    end

    test "uses query variable defaults when supplied_vars are not provided (PostgreSQL)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        variables: [
          %{name: "min_age", type: :number, default: "40"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE age > $1"
      assert params == [40]
    end

    test "uses query variable defaults when supplied_vars are not provided (SQLite)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        variables: [
          %{name: "min_age", type: :number, default: "40"}
        ],
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE age > ?"
      assert params == [40]
    end

    test "raises if required variable missing and there is no query variable default" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        variables: []
      }

      assert_raise ArgumentError, ~r/Missing required variable: min_age/, fn ->
        Query.to_sql_params(q, %{})
      end
    end


    test "ignores unused query variables" do
      q = %Query{
        statement: "SELECT * FROM users",
        variables: [
          %{name: "unused", type: :text, default: "value"}
        ]
      }

      {sql, params} = Query.to_sql_params(q, %{})
      assert sql == "SELECT * FROM users"
      assert params == []
    end

    test "handles multiple occurrences of the same variable (PostgreSQL)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE name = {{name}} OR nickname = {{name}}",
        variables: [
          %{name: "name", type: :text, default: "Jack"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE name = $1 OR nickname = $2"
      assert params == ["Jack", "Jack"]
    end

    test "handles multiple occurrences of the same variable (SQLite)" do
      q = %Query{
        statement: "SELECT * FROM users WHERE name = {{name}} OR nickname = {{name}}",
        variables: [
          %{name: "name", type: :text, default: "Jack"}
        ],
        data_repo: "sqlite"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE name = ? OR nickname = ?"
      assert params == ["Jack", "Jack"]
    end


    test "overrides query variable defaults with provided supplied_vars" do
      q = %Query{
        statement: "SELECT * FROM users WHERE status = {{status}}",
        variables: [
          %{name: "status", type: :text, default: "inactive"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"status" => "active"})

      assert sql == "SELECT * FROM users WHERE status = $1"
      assert params == ["active"]
    end

    test "raises when nil value is provided" do
      q = %Query{
        statement: "SELECT * FROM users WHERE deleted_at IS {{deleted}}",
        variables: [],
        data_repo: "postgres"
      }

      assert_raise ArgumentError, ~r/Missing required variable: deleted/, fn ->
        Query.to_sql_params(q, %{"deleted" => nil})
      end
    end

    test "preserves var order in params list" do
      q = %Query{
        statement: "INSERT INTO users (name, age, email) VALUES ({{name}}, {{age}}, {{email}})",
        variables: [],
        data_repo: "postgres"
      }

      {sql, params} =
        Query.to_sql_params(q, %{"name" => "John", "age" => 30, "email" => "john@example.com"})

      assert sql == "INSERT INTO users (name, age, email) VALUES ($1, $2, $3)"
      assert params == ["John", 30, "john@example.com"]
    end

    test "encloses a text literal in single quotes" do
    end
  end

  describe "variables field" do
    test "accepts valid variables" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users WHERE org_id = {{org_id}} AND status = {{status}}",
        variables: [
          %{name: "org_id", type: :number, label: "Organization ID", default: "1"},
          %{name: "status", type: :text, label: "Status", default: "active"}
        ]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      variables = get_field(changeset, :variables)
      assert length(variables) == 2

      org_var = Enum.find(variables, &(&1.name == "org_id"))
      assert org_var.type == :number
      assert org_var.label == "Organization ID"
      assert org_var.default == "1"

      status_var = Enum.find(variables, &(&1.name == "status"))
      assert status_var.type == :text
      assert status_var.label == "Status"
      assert status_var.default == "active"
    end

    test "accepts variables with select widgets and static_options" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users WHERE status = {{status}}",
        variables: [
          %{
            name: "status",
            type: :text,
            widget: :select,
            label: "Status",
            static_options: ["active", "inactive", "pending"]
          }
        ]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      variables = get_field(changeset, :variables)
      status_var = hd(variables)
      assert status_var.widget == :select
      assert status_var.static_options == ["active", "inactive", "pending"]
    end

    test "accepts variables with select widgets and options_query" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users WHERE org_id = {{org_id}}",
        variables: [
          %{
            name: "org_id",
            type: :number,
            widget: :select,
            label: "Organization",
            options_query: "SELECT id, name FROM orgs ORDER BY name"
          }
        ]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      variables = get_field(changeset, :variables)
      org_var = hd(variables)
      assert org_var.widget == :select
      assert org_var.options_query == "SELECT id, name FROM orgs ORDER BY name"
    end

    test "rejects variables with invalid types" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users",
        variables: [
          %{name: "invalid", type: :invalid_type, label: "Invalid"}
        ]
      }

      changeset = Query.new(attrs)

      refute changeset.valid?
      assert %{variables: [%{type: ["is invalid"]}]} = errors_on(changeset)
    end

    test "rejects variables with invalid widgets" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users",
        variables: [
          %{name: "test", type: :text, widget: :invalid_widget, label: "Test"}
        ]
      }

      changeset = Query.new(attrs)

      refute changeset.valid?
      assert %{variables: [%{widget: ["is invalid"]}]} = errors_on(changeset)
    end

    test "rejects select widgets without options" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users WHERE status = {{status}}",
        variables: [
          %{
            name: "status",
            type: :text,
            widget: :select,
            label: "Status"
          }
        ]
      }

      changeset = Query.new(attrs)

      refute changeset.valid?

      assert %{
               variables: [
                 %{widget: ["select must define either static_options or options_query"]}
               ]
             } = errors_on(changeset)
    end

    test "sets default widget to input when not specified" do
      attrs = %{
        name: "Test Query",
        statement: "SELECT * FROM users WHERE name = {{name}}",
        variables: [
          %{name: "name", type: :text, label: "Name"}
        ]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      variables = get_field(changeset, :variables)
      name_var = hd(variables)
      assert name_var.widget == :input
    end
  end

  describe "variable type casting" do
    test "casts number type from string" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        variables: [
          %{name: "min_age", type: :number, default: "30"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE age > $1"
      assert params == [30]
    end

    test "casts date type from string" do
      q = %Query{
        statement: "SELECT * FROM users WHERE created_at >= {{since}}",
        variables: [
          %{name: "since", type: :date, default: "2024-01-01"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE created_at >= $1"
      assert params == [~D[2024-01-01]]
    end

    test "handles text type without casting" do
      q = %Query{
        statement: "SELECT * FROM users WHERE status = {{status}}",
        variables: [
          %{name: "status", type: :text, default: "active"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{})

      assert sql == "SELECT * FROM users WHERE status = $1"
      assert params == ["active"]
    end

    test "casts runtime supplied values" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}} AND created_at >= {{since}}",
        variables: [
          %{name: "min_age", type: :number},
          %{name: "since", type: :date}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"min_age" => "25", "since" => "2024-06-01"})

      assert sql == "SELECT * FROM users WHERE age > $1 AND created_at >= $2"
      assert params == [25, ~D[2024-06-01]]
    end

    test "runtime values override defaults with casting" do
      q = %Query{
        statement: "SELECT * FROM users WHERE age > {{min_age}}",
        variables: [
          %{name: "min_age", type: :number, default: "30"}
        ],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"min_age" => "45"})

      assert sql == "SELECT * FROM users WHERE age > $1"
      assert params == [45]
    end

    test "handles variables without type metadata" do
      q = %Query{
        statement: "SELECT * FROM users WHERE name = {{name}}",
        variables: [],
        data_repo: "postgres"
      }

      {sql, params} = Query.to_sql_params(q, %{"name" => "John"})

      assert sql == "SELECT * FROM users WHERE name = $1"
      assert params == ["John"]
    end
  end

  describe "comprehensive variable scenarios" do
    test "complex query with mixed variable types and widgets" do
      attrs = %{
        name: "User Report",
        statement: """
        SELECT u.* FROM users u
        WHERE u.org_id = {{org_id}}
          AND u.created_at >= {{since_date}}
          AND u.status = {{status}}
          AND u.age > {{min_age}}
        """,
        variables: [
          %{
            name: "org_id",
            type: :number,
            widget: :select,
            label: "Organization",
            options_query: "SELECT id, name FROM orgs ORDER BY name"
          },
          %{
            name: "since_date",
            type: :date,
            label: "Created Since",
            default: "2024-01-01"
          },
          %{
            name: "status",
            type: :text,
            widget: :select,
            label: "Status",
            static_options: ["active", "inactive", "pending"],
            default: "active"
          },
          %{
            name: "min_age",
            type: :number,
            label: "Minimum Age",
            default: "18"
          }
        ]
      }

      changeset = Query.new(attrs)
      assert changeset.valid?

      # Test with the query struct
      q = %Query{
        statement: String.trim(attrs.statement),
        variables: get_field(changeset, :variables),
        data_repo: "postgres"
      }

      # org_id has no default, so it should raise an error when called with empty vars
      assert_raise ArgumentError, ~r/Missing required variable: org_id/, fn ->
        Query.to_sql_params(q, %{})
      end

      # Test with runtime values
      {sql, params} =
        Query.to_sql_params(q, %{
          "org_id" => "5",
          "since_date" => "2024-06-01",
          "status" => "pending",
          "min_age" => "25"
        })

      expected_sql =
        "SELECT u.* FROM users u\nWHERE u.org_id = $1\n  AND u.created_at >= $2\n  AND u.status = $3\n  AND u.age > $4"

      assert sql == expected_sql
      assert params == [5, ~D[2024-06-01], "pending", 25]
    end

    test "handles validation errors in variable definitions" do
      attrs = %{
        name: "Invalid Query",
        statement: "SELECT * FROM users",
        variables: [
          # Missing required name field
          %{type: :text, label: "Test"},
          # Missing required type field
          %{name: "test2", label: "Test 2"},
          # Select widget without options
          %{name: "test3", type: :text, widget: :select, label: "Test 3"}
        ]
      }

      changeset = Query.new(attrs)

      refute changeset.valid?
      errors = errors_on(changeset)

      assert %{variables: variable_errors} = errors
      assert length(variable_errors) == 3

      # Check specific error patterns
      assert Enum.any?(variable_errors, fn errors ->
               Map.has_key?(errors, :name) and "can't be blank" in errors.name
             end)

      assert Enum.any?(variable_errors, fn errors ->
               Map.has_key?(errors, :type) and "can't be blank" in errors.type
             end)

      assert Enum.any?(variable_errors, fn errors ->
               Map.has_key?(errors, :widget) and
                 "select must define either static_options or options_query" in errors.widget
             end)
    end
  end
end
