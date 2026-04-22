defmodule Lotus.Source.Adapters.Ecto.Dialects.DefaultTest do
  # Not async: mutates :persistent_term rate-limit state shared across BEAM.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lotus.Source.Adapters.Ecto.Dialects.Default

  # Minimal repo stub — Default.execute_in_transaction only needs
  # repo.transaction/2 and repo.__adapter__/0 for the warning path.
  defmodule FakeRepo do
    def transaction(fun, _opts), do: {:ok, fun.()}
    def __adapter__, do: :fake_ecto_adapter
  end

  setup do
    :persistent_term.erase({Default, :read_only_warned, FakeRepo})
    on_exit(fn -> :persistent_term.erase({Default, :read_only_warned, FakeRepo}) end)
    :ok
  end

  describe "execute_in_transaction/3 read-only warning" do
    test "warns the first time read_only is requested and cannot be enforced" do
      log =
        capture_log(fn ->
          assert {:ok, :done} = Default.execute_in_transaction(FakeRepo, fn -> :done end, [])
        end)

      assert log =~ "cannot enforce read-only transactions"
      assert log =~ inspect(FakeRepo)
      assert log =~ ":fake_ecto_adapter"
    end

    test "rate-limits the warning to once per {dialect, repo}" do
      first =
        capture_log(fn ->
          Default.execute_in_transaction(FakeRepo, fn -> :ok end, [])
        end)

      second =
        capture_log(fn ->
          Default.execute_in_transaction(FakeRepo, fn -> :ok end, [])
        end)

      assert first =~ "cannot enforce read-only transactions"
      refute second =~ "cannot enforce read-only transactions"
    end

    test "does not warn when caller explicitly opts out via read_only: false" do
      log =
        capture_log(fn ->
          Default.execute_in_transaction(FakeRepo, fn -> :ok end, read_only: false)
        end)

      refute log =~ "cannot enforce read-only transactions"
    end
  end
end
