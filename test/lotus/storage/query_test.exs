defmodule Lotus.Storage.QueryTest do
  use Lotus.Case, async: true

  alias Lotus.Storage.Query

  describe "new/1" do
    test "builds a valid changeset with required fields" do
      attrs = %{
        name: "Recent Users",
        query: %{sql: "SELECT * FROM users WHERE active = true", params: []},
        tags: ["Users", "  ACTIVE  ", "users"]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      assert get_field(changeset, :name) == "Recent Users"

      assert get_field(changeset, :query) == %{
               sql: "SELECT * FROM users WHERE active = true",
               params: []
             }

      assert get_field(changeset, :tags) == ["users", "active"]
    end

    test "builds valid changeset with string keys" do
      attrs = %{
        name: "User Count",
        query: %{"sql" => "SELECT count(*) FROM users", "params" => []},
        tags: ["analytics"]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      assert get_field(changeset, :name) == "User Count"

      assert get_field(changeset, :query) == %{
               "sql" => "SELECT count(*) FROM users",
               "params" => []
             }

      assert get_field(changeset, :tags) == ["analytics"]
    end

    test "builds valid changeset without params" do
      attrs = %{
        name: "All Users",
        query: %{sql: "SELECT * FROM users"}
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      assert get_field(changeset, :name) == "All Users"
      assert get_field(changeset, :query) == %{sql: "SELECT * FROM users"}
      assert get_field(changeset, :tags) == []
    end

    test "is invalid without required fields" do
      changeset = Query.new(%{})

      refute changeset.valid?
      assert %{name: ["can't be blank"], query: ["can't be blank"]} = errors_on(changeset)
    end

    test "is invalid when name is empty" do
      changeset = Query.new(%{name: "", query: %{sql: "SELECT 1"}})

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "is invalid when query has no sql" do
      changeset = Query.new(%{name: "Test", query: %{params: []}})

      refute changeset.valid?

      assert %{query: ["must include sql (string) and optionally params (list)"]} =
               errors_on(changeset)
    end

    test "is invalid when query sql is empty" do
      changeset = Query.new(%{name: "Test", query: %{sql: "   "}})

      refute changeset.valid?
      assert %{query: ["sql cannot be empty"]} = errors_on(changeset)
    end

    test "is invalid when query params is not a list" do
      changeset = Query.new(%{name: "Test", query: %{sql: "SELECT 1", params: "invalid"}})

      refute changeset.valid?
      assert %{query: ["params must be a list when present"]} = errors_on(changeset)
    end

    test "normalizes tags by trimming, downcasing, and removing duplicates" do
      attrs = %{
        name: "Test Query",
        query: %{sql: "SELECT 1"},
        tags: ["  Analytics  ", "REPORTING", "analytics", "", "reporting"]
      }

      changeset = Query.new(attrs)

      assert changeset.valid?
      assert get_field(changeset, :tags) == ["analytics", "reporting"]
    end

    test "accepts valid search_path" do
      attrs = %{
        name: "Schema Query",
        query: %{sql: "SELECT * FROM users"},
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
          query: %{sql: "SELECT 1"},
          search_path: "analytics"
        })

      assert changeset.valid?
      assert get_field(changeset, :search_path) == "analytics"
    end

    test "converts empty search_path to nil" do
      changeset =
        Query.new(%{
          name: "Test",
          query: %{sql: "SELECT 1"},
          search_path: ""
        })

      assert changeset.valid?
      assert get_field(changeset, :search_path) == nil
    end

    test "is invalid with malformed search_path" do
      changeset =
        Query.new(%{
          name: "Test",
          query: %{sql: "SELECT 1"},
          search_path: "invalid-schema, 123schema"
        })

      refute changeset.valid?

      assert %{
               search_path: [
                 "must be a comma-separated list of valid schema identifiers (letters, numbers, underscores only)"
               ]
             } =
               errors_on(changeset)
    end

    test "is invalid when search_path is not a string" do
      changeset =
        Query.new(%{
          name: "Test",
          query: %{sql: "SELECT 1"},
          search_path: 123
        })

      refute changeset.valid?
      assert %{search_path: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "update/2" do
    setup do
      {:ok, query: %Query{name: "Original", query: %{sql: "SELECT 1"}, tags: ["foo"]}}
    end

    test "updates fields and normalizes tags", %{query: query} do
      changeset = Query.update(query, %{name: "Updated", tags: [" Foo ", "bar", "BAR"]})

      assert changeset.valid?
      assert get_field(changeset, :name) == "Updated"
      assert get_field(changeset, :tags) == ["foo", "bar"]
    end

    test "validates updated query payload", %{query: query} do
      changeset = Query.update(query, %{query: %{sql: ""}})

      refute changeset.valid?
      assert %{query: ["sql cannot be empty"]} = errors_on(changeset)
    end
  end

  describe "to_sql_params/1" do
    test "extracts sql and params with string keys" do
      query = %Query{query: %{"sql" => "SELECT * FROM users WHERE id = $1", "params" => [123]}}

      assert Query.to_sql_params(query) == {"SELECT * FROM users WHERE id = $1", [123]}
    end

    test "extracts sql and params with atom keys" do
      query = %Query{query: %{sql: "SELECT * FROM users WHERE id = $1", params: [123]}}

      assert Query.to_sql_params(query) == {"SELECT * FROM users WHERE id = $1", [123]}
    end

    test "handles missing params with string keys" do
      query = %Query{query: %{"sql" => "SELECT * FROM users"}}

      assert Query.to_sql_params(query) == {"SELECT * FROM users", []}
    end

    test "handles missing params with atom keys" do
      query = %Query{query: %{sql: "SELECT * FROM users"}}

      assert Query.to_sql_params(query) == {"SELECT * FROM users", []}
    end

    test "handles nil params with string keys" do
      query = %Query{query: %{"sql" => "SELECT * FROM users", "params" => nil}}

      assert Query.to_sql_params(query) == {"SELECT * FROM users", []}
    end

    test "handles nil params with atom keys" do
      query = %Query{query: %{sql: "SELECT * FROM users", params: nil}}

      assert Query.to_sql_params(query) == {"SELECT * FROM users", []}
    end
  end
end
