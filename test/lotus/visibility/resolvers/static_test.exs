defmodule Lotus.Visibility.Resolvers.StaticTest do
  use ExUnit.Case
  use Mimic

  alias Lotus.Visibility.Resolvers.Static

  setup do
    Mimic.copy(Lotus.Config)
    :ok
  end

  describe "schema_rules_for/1" do
    test "returns schema rules for configured repo name" do
      schema_rules = [
        allow: ["public", "analytics"],
        deny: ["restricted"]
      ]

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn repo_name ->
        if repo_name == "postgres", do: schema_rules, else: []
      end)

      assert Static.schema_rules_for("postgres") == schema_rules
    end

    test "falls back to default rules for unknown repo names" do
      default_rules = [allow: ["public"], deny: []]

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn _repo_name -> default_rules end)

      assert Static.schema_rules_for("unknown_repo") == default_rules
    end

    test "returns empty list when no rules configured" do
      Lotus.Config |> stub(:schema_rules_for_repo_name, fn _repo_name -> [] end)

      assert Static.schema_rules_for("postgres") == []
      assert Static.schema_rules_for("mysql") == []
    end

    test "handles regex patterns in rules" do
      schema_rules = [
        allow: [~r/^tenant_/],
        deny: [~r/^temp_/]
      ]

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn _repo_name -> schema_rules end)

      assert Static.schema_rules_for("postgres") == schema_rules
    end
  end

  describe "table_rules_for/1" do
    test "returns table rules for configured repo name" do
      table_rules = [
        allow: [
          {"public", "users"},
          {"public", ~r/^dim_/}
        ],
        deny: ["api_keys"]
      ]

      Lotus.Config
      |> stub(:rules_for_repo_name, fn repo_name ->
        if repo_name == "postgres", do: table_rules, else: []
      end)

      assert Static.table_rules_for("postgres") == table_rules
    end

    test "falls back to default rules for unknown repo names" do
      default_rules = [allow: [], deny: ["sensitive_data"]]

      Lotus.Config
      |> stub(:rules_for_repo_name, fn _repo_name -> default_rules end)

      assert Static.table_rules_for("unknown_repo") == default_rules
    end

    test "returns empty list when no rules configured" do
      Lotus.Config |> stub(:rules_for_repo_name, fn _repo_name -> [] end)

      assert Static.table_rules_for("postgres") == []
      assert Static.table_rules_for("mysql") == []
    end

    test "supports various rule formats" do
      table_rules = [
        allow: [
          "public_table",
          {"schema", "table"},
          {nil, "sqlite_table"},
          {"schema", ~r/^dim_/}
        ],
        deny: [~r/^temp_/]
      ]

      Lotus.Config
      |> stub(:rules_for_repo_name, fn _repo_name -> table_rules end)

      assert Static.table_rules_for("postgres") == table_rules
    end
  end

  describe "column_rules_for/1" do
    test "returns column rules for configured repo name" do
      column_rules = [
        {nil, "passwords", :omit},
        {"public", "users", "ssn", :mask},
        {"public", "users", "email", [action: :mask, mask: :sha256]}
      ]

      Lotus.Config
      |> stub(:column_rules_for_repo_name, fn repo_name ->
        if repo_name == "postgres", do: column_rules, else: []
      end)

      assert Static.column_rules_for("postgres") == column_rules
    end

    test "falls back to default rules for unknown repo names" do
      default_rules = [
        {nil, ~r/^api_/, :omit}
      ]

      Lotus.Config
      |> stub(:column_rules_for_repo_name, fn _repo_name -> default_rules end)

      assert Static.column_rules_for("unknown_repo") == default_rules
    end

    test "returns empty list when no rules configured" do
      Lotus.Config |> stub(:column_rules_for_repo_name, fn _repo_name -> [] end)

      assert Static.column_rules_for("postgres") == []
      assert Static.column_rules_for("mysql") == []
    end

    test "handles complex masking policies" do
      column_rules = [
        {nil, "passwords", [action: :mask, mask: :null]},
        {"public", "credit_cards",
         [
           action: :mask,
           mask: {:partial, keep_last: 4, replacement: "*"},
           show_in_schema?: false
         ]},
        {nil, ~r/^internal_/, :error}
      ]

      Lotus.Config
      |> stub(:column_rules_for_repo_name, fn _repo_name -> column_rules end)

      assert Static.column_rules_for("postgres") == column_rules
    end
  end

  describe "behaviour compliance" do
    test "implements Lotus.Visibility.Resolver behaviour" do
      assert :lists.member(
               Lotus.Visibility.Resolver,
               Static.__info__(:attributes) |> Keyword.get(:behaviour, [])
             )
    end

    test "has all required callbacks" do
      required_callbacks = [
        {:schema_rules_for, 1},
        {:table_rules_for, 1},
        {:column_rules_for, 1}
      ]

      exported_functions = Static.__info__(:functions)

      Enum.each(required_callbacks, fn {name, arity} ->
        assert {name, arity} in exported_functions,
               "Missing required callback #{name}/#{arity}"
      end)
    end
  end

  describe "realistic configuration scenarios" do
    test "typical data warehouse setup" do
      schema_rules = [
        allow: ["public", "analytics", ~r/^tenant_/],
        deny: ["staging"]
      ]

      table_rules = [
        allow: [
          {"public", ~r/^dim_/},
          {"public", ~r/^fact_/},
          {"analytics", ~r/.*/}
        ],
        deny: [
          {"public", ~r/^staging_/},
          {"public", ~r/_temp$/}
        ]
      ]

      column_rules = [
        {nil, "api_keys", :omit},
        {nil, "passwords", [action: :mask, mask: :null]},
        {"public", "users", "ssn", :mask}
      ]

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn _repo_name -> schema_rules end)
      |> stub(:rules_for_repo_name, fn _repo_name -> table_rules end)
      |> stub(:column_rules_for_repo_name, fn _repo_name -> column_rules end)

      assert Static.schema_rules_for("postgres") == schema_rules
      assert Static.table_rules_for("postgres") == table_rules
      assert Static.column_rules_for("postgres") == column_rules
    end

    test "simple business database with basic deny rules" do
      schema_rules = [allow: [], deny: []]

      table_rules = [
        allow: [],
        deny: [
          "user_passwords",
          ~r/^audit_/,
          ~r/_log$/
        ]
      ]

      column_rules = [
        {nil, "credit_cards", :omit},
        {nil, "social_security_number", :omit}
      ]

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn _repo_name -> schema_rules end)
      |> stub(:rules_for_repo_name, fn _repo_name -> table_rules end)
      |> stub(:column_rules_for_repo_name, fn _repo_name -> column_rules end)

      assert Static.schema_rules_for("postgres") == schema_rules
      assert Static.table_rules_for("postgres") == table_rules
      assert Static.column_rules_for("postgres") == column_rules
    end

    test "multi-database MySQL setup" do
      schema_rules = [
        allow: ["app_db", "analytics_db"],
        deny: ["staging_db", "test_db"]
      ]

      table_rules = [
        allow: [
          {"app_db", ~r/.*/},
          {"analytics_db", ~r/.*/}
        ],
        deny: []
      ]

      column_rules = []

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn _repo_name -> schema_rules end)
      |> stub(:rules_for_repo_name, fn _repo_name -> table_rules end)
      |> stub(:column_rules_for_repo_name, fn _repo_name -> column_rules end)

      assert Static.schema_rules_for("mysql") == schema_rules
      assert Static.table_rules_for("mysql") == table_rules
      assert Static.column_rules_for("mysql") == column_rules
    end
  end

  describe "consistency with Config functions" do
    test "schema_rules_for delegates directly to Config.schema_rules_for_repo_name" do
      test_rules = [allow: ["public"], deny: []]

      Lotus.Config
      |> stub(:schema_rules_for_repo_name, fn repo_name ->
        if repo_name == "test_repo", do: test_rules, else: []
      end)

      result = Static.schema_rules_for("test_repo")
      assert result == test_rules
    end

    test "table_rules_for delegates directly to Config.rules_for_repo_name" do
      test_rules = [allow: [{"public", "users"}], deny: []]

      Lotus.Config
      |> stub(:rules_for_repo_name, fn repo_name ->
        if repo_name == "test_repo", do: test_rules, else: []
      end)

      result = Static.table_rules_for("test_repo")
      assert result == test_rules
    end

    test "column_rules_for delegates directly to Config.column_rules_for_repo_name" do
      test_rules = [{nil, "passwords", :omit}]

      Lotus.Config
      |> stub(:column_rules_for_repo_name, fn repo_name ->
        if repo_name == "test_repo", do: test_rules, else: []
      end)

      result = Static.column_rules_for("test_repo")
      assert result == test_rules
    end
  end
end
