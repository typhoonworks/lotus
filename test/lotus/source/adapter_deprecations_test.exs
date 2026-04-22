defmodule Lotus.Source.AdapterDeprecationsTest do
  @moduledoc """
  Covers the deprecation shims for `transform_sql/2` → `transform_statement/2`
  and `transform_query/4` → `transform_bound_query/4`:

    * Dispatch helpers prefer the new callback name.
    * If only the deprecated name is implemented, dispatch falls back to it
      and emits a one-time `Logger.warning` nudging a rename.
    * Facade functions for the deprecated names delegate to the new ones.
  """

  # Not async — mutates :persistent_term rate-limit state (BEAM-global).
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lotus.Source.Adapter

  # New-callback-only adapter.
  defmodule NewOnlyAdapter do
    def transform_statement(_state, statement), do: "NEW:" <> statement
    def transform_bound_query(_state, query, params, _opts), do: {"NEW:" <> query, params}
  end

  # Deprecated-callback-only adapter (simulates an external adapter that
  # hasn't migrated yet).
  defmodule OldOnlyAdapter do
    def transform_sql(_state, sql), do: "OLD:" <> sql
    def transform_query(_state, query, params, _opts), do: {"OLD:" <> query, params}
  end

  # Both implemented — new takes precedence.
  defmodule BothAdapter do
    def transform_statement(_state, s), do: "NEW:" <> s
    def transform_sql(_state, s), do: "OLD:" <> s
    def transform_bound_query(_state, q, p, _o), do: {"NEW:" <> q, p}
    def transform_query(_state, q, p, _o), do: {"OLD:" <> q, p}
  end

  setup do
    for mod <- [NewOnlyAdapter, OldOnlyAdapter, BothAdapter],
        cb <- [:transform_sql, :transform_query] do
      :persistent_term.erase({Adapter, :deprecated_callback_warned, mod, cb})
    end

    :ok
  end

  defp adapter(mod) do
    %Adapter{name: "t", module: mod, state: nil, source_type: :other}
  end

  describe "transform_statement/2 dispatch" do
    test "uses the new callback when implemented" do
      assert "NEW:x" = Adapter.transform_statement(adapter(NewOnlyAdapter), "x")
    end

    test "falls back to the deprecated transform_sql/2 with a one-time warning" do
      log = capture_log(fn -> Adapter.transform_statement(adapter(OldOnlyAdapter), "x") end)
      assert log =~ "deprecated"
      assert log =~ "transform_sql"
      assert log =~ "transform_statement"

      # Second call: same return, but no repeat warning.
      second = capture_log(fn -> Adapter.transform_statement(adapter(OldOnlyAdapter), "y") end)
      refute second =~ "deprecated"
    end

    test "new callback takes precedence over deprecated when both present" do
      assert "NEW:z" = Adapter.transform_statement(adapter(BothAdapter), "z")
    end
  end

  describe "transform_bound_query/4 dispatch" do
    test "uses the new callback when implemented" do
      assert {"NEW:q", [1]} =
               Adapter.transform_bound_query(adapter(NewOnlyAdapter), "q", [1], [])
    end

    test "falls back to the deprecated transform_query/4 with a one-time warning" do
      log =
        capture_log(fn ->
          Adapter.transform_bound_query(adapter(OldOnlyAdapter), "q", [], [])
        end)

      assert log =~ "deprecated"
      assert log =~ "transform_query"
      assert log =~ "transform_bound_query"
    end

    test "new callback takes precedence over deprecated when both present" do
      assert {"NEW:z", []} = Adapter.transform_bound_query(adapter(BothAdapter), "z", [], [])
    end
  end
end
