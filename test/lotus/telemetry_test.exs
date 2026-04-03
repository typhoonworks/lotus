defmodule Lotus.TelemetryTest do
  use Lotus.Case, async: true

  alias Lotus.Fixtures
  alias Lotus.Runner
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter
  alias Lotus.Test.Repo

  @pg_adapter EctoAdapter.wrap("postgres", Repo)

  setup do
    fixtures = Fixtures.setup_test_data()
    {:ok, fixtures}
  end

  describe "query telemetry events" do
    test "emits start and stop events on successful query" do
      ref = make_ref()
      pid = self()

      :telemetry.attach_many(
        "#{inspect(ref)}",
        [[:lotus, :query, :start], [:lotus, :query, :stop]],
        fn event, measurements, metadata, _ ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _result} = Runner.run_sql(@pg_adapter, "SELECT 1 AS num")

      assert_received {:telemetry, [:lotus, :query, :start], %{system_time: _},
                       %{repo: "postgres", sql: "SELECT 1 AS num"}}

      assert_received {:telemetry, [:lotus, :query, :stop], measurements,
                       %{repo: "postgres", sql: "SELECT 1 AS num", result: %Lotus.Result{}}}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert measurements.row_count >= 0

      :telemetry.detach("#{inspect(ref)}")
    end

    test "emits start and exception events on failed query" do
      ref = make_ref()
      pid = self()

      :telemetry.attach_many(
        "#{inspect(ref)}",
        [[:lotus, :query, :start], [:lotus, :query, :exception]],
        fn event, measurements, metadata, _ ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:error, _} = Runner.run_sql(@pg_adapter, "DROP TABLE test_users")

      assert_received {:telemetry, [:lotus, :query, :start], %{system_time: _},
                       %{repo: "postgres", sql: "DROP TABLE test_users"}}

      assert_received {:telemetry, [:lotus, :query, :exception], measurements,
                       %{kind: :error, repo: "postgres", sql: "DROP TABLE test_users"}}

      assert is_integer(measurements.duration)

      :telemetry.detach("#{inspect(ref)}")
    end
  end

  describe "schema introspection telemetry events" do
    @tag :sqlite
    test "emits start and stop events for list_tables" do
      ref = make_ref()
      pid = self()

      :telemetry.attach_many(
        "#{inspect(ref)}",
        [
          [:lotus, :schema, :introspection, :start],
          [:lotus, :schema, :introspection, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _tables} = Lotus.Schema.list_tables("sqlite")

      assert_received {:telemetry, [:lotus, :schema, :introspection, :start], %{system_time: _},
                       %{operation: :list_tables, repo: "sqlite"}}

      assert_received {:telemetry, [:lotus, :schema, :introspection, :stop],
                       %{duration: duration},
                       %{operation: :list_tables, repo: "sqlite", result: :ok}}

      assert is_integer(duration)
      assert duration >= 0

      :telemetry.detach("#{inspect(ref)}")
    end

    @tag :sqlite
    test "emits start and stop events for get_table_schema" do
      ref = make_ref()
      pid = self()

      :telemetry.attach_many(
        "#{inspect(ref)}",
        [
          [:lotus, :schema, :introspection, :start],
          [:lotus, :schema, :introspection, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _schema} = Lotus.Schema.get_table_schema("sqlite", "products")

      assert_received {:telemetry, [:lotus, :schema, :introspection, :start], _,
                       %{operation: :get_table_schema, repo: "sqlite"}}

      assert_received {:telemetry, [:lotus, :schema, :introspection, :stop], %{duration: _},
                       %{operation: :get_table_schema, repo: "sqlite", result: :ok}}

      :telemetry.detach("#{inspect(ref)}")
    end

    @tag :sqlite
    test "emits start and stop events for list_schemas" do
      ref = make_ref()
      pid = self()

      :telemetry.attach_many(
        "#{inspect(ref)}",
        [
          [:lotus, :schema, :introspection, :start],
          [:lotus, :schema, :introspection, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _schemas} = Lotus.Schema.list_schemas("sqlite")

      assert_received {:telemetry, [:lotus, :schema, :introspection, :start], _,
                       %{operation: :list_schemas, repo: "sqlite"}}

      assert_received {:telemetry, [:lotus, :schema, :introspection, :stop], %{duration: _},
                       %{operation: :list_schemas, result: :ok}}

      :telemetry.detach("#{inspect(ref)}")
    end
  end
end
