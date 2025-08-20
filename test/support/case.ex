defmodule Lotus.Case do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Usher.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Lotus.Test.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Lotus.Case
    end
  end

  setup context do
    # Always setup PostgreSQL sandbox (for Lotus storage)
    pid1 = Ecto.Adapters.SQL.Sandbox.start_owner!(Lotus.Test.Repo, shared: not context[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid1) end)
    
    # If test needs SQLite, set up SQLite sandbox too
    if context[:sqlite] do
      pid2 = Ecto.Adapters.SQL.Sandbox.start_owner!(Lotus.Test.SqliteRepo, shared: not context[:async])
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid2) end)
    end

    :ok
  end

  @doc """
  Transforms changeset errors into a map of messages for easy assertions.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
