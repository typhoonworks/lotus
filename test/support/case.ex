defmodule Lotus.Case do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
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
      pid2 =
        Ecto.Adapters.SQL.Sandbox.start_owner!(Lotus.Test.SqliteRepo, shared: not context[:async])

      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid2) end)
    end

    :ok
  end

  @doc """
  Transforms changeset errors into a map of messages for easy assertions.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
