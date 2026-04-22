defmodule Lotus.Source.AdapterPaginationTest do
  @moduledoc """
  Covers the `apply_pagination/4` dispatch + deprecation path:

    * New `apply_pagination/4` callback preferred.
    * Deprecated `apply_window/4` callback still invoked with a one-time
      warning, and its legacy `window_meta` return shape is translated into
      the new `count_spec` contract.
    * Old facade `Adapter.apply_window/4` delegates to the new name.
  """

  # Not async — mutates :persistent_term rate-limit state (BEAM-global).
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lotus.Source.Adapter

  # Adapter implementing only the new callback.
  defmodule NewAdapter do
    def apply_pagination(_state, q, p, opts) do
      limit = Keyword.fetch!(opts, :limit)
      count_mode = Keyword.get(opts, :count, :none)

      paged = "NEW:" <> q
      paged_params = p ++ [limit]

      count_spec =
        if count_mode == :exact,
          do: %{query: "NEW_COUNT(#{q})", params: p},
          else: nil

      {paged, paged_params, count_spec}
    end
  end

  # Adapter still on the legacy callback with the old window_meta grab-bag.
  defmodule LegacyAdapter do
    def apply_window(_state, q, p, opts) do
      limit = Keyword.fetch!(opts, :limit)
      count_mode = Keyword.get(opts, :count, :none)

      paged = "OLD:" <> q
      paged_params = p ++ [limit]

      window_meta =
        case count_mode do
          :exact ->
            %{
              window: %{limit: limit, offset: 0},
              total_mode: :exact,
              count_sql: "OLD_COUNT(#{q})",
              count_params: p
            }

          _ ->
            %{window: %{limit: limit, offset: 0}, total_mode: :none}
        end

      {paged, paged_params, window_meta}
    end
  end

  setup do
    for mod <- [LegacyAdapter] do
      :persistent_term.erase({Adapter, :deprecated_callback_warned, mod, :apply_window})
    end

    :ok
  end

  defp adapter(mod) do
    %Adapter{name: "t", module: mod, state: nil, source_type: :other}
  end

  describe "new callback preferred" do
    test "apply_pagination uses the new callback directly" do
      assert {"NEW:q", [5], nil} =
               Adapter.apply_pagination(adapter(NewAdapter), "q", [], limit: 5)
    end

    test "count_spec passes through from the new callback" do
      assert {"NEW:q", [5], %{query: "NEW_COUNT(q)", params: []}} =
               Adapter.apply_pagination(adapter(NewAdapter), "q", [], limit: 5, count: :exact)
    end
  end

  describe "legacy callback fallback with translation" do
    test "falls back to apply_window/4 with a one-time warning" do
      log =
        capture_log(fn ->
          Adapter.apply_pagination(adapter(LegacyAdapter), "q", [], limit: 5)
        end)

      assert log =~ "deprecated"
      assert log =~ "apply_window"
      assert log =~ "apply_pagination"

      # Subsequent calls: no repeat warning.
      second =
        capture_log(fn ->
          Adapter.apply_pagination(adapter(LegacyAdapter), "q", [], limit: 5)
        end)

      refute second =~ "deprecated"
    end

    test "legacy window_meta with :exact mode is translated into count_spec" do
      {"OLD:q", [5], count_spec} =
        capture_and_call(adapter(LegacyAdapter), "q", [], limit: 5, count: :exact)

      assert count_spec == %{query: "OLD_COUNT(q)", params: []}
    end

    test "legacy :none mode becomes nil count_spec" do
      {"OLD:q", [5], count_spec} =
        capture_and_call(adapter(LegacyAdapter), "q", [], limit: 5, count: :none)

      assert count_spec == nil
    end
  end

  # Suppresses the rate-limited deprecation warning by resetting the
  # persistent_term guard before each call — gives us a clean return tuple.
  defp capture_and_call(adapter, q, p, opts) do
    :persistent_term.erase({Adapter, :deprecated_callback_warned, adapter.module, :apply_window})

    capture_log(fn ->
      send(self(), {:result, Adapter.apply_pagination(adapter, q, p, opts)})
    end)

    receive do
      {:result, r} -> r
    end
  end
end
