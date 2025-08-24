Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sqlite3)

Enum.each([Lotus.Test.Repo, Lotus.Test.SqliteRepo], fn repo ->
  _ = repo.__adapter__().storage_up(repo.config())
end)

{:ok, _} = Lotus.Test.Repo.start_link()
{:ok, _} = Lotus.Test.SqliteRepo.start_link()

pg_path = Path.join([File.cwd!(), "test/support/postgres/migrations"])
sq_path = Path.join([File.cwd!(), "test/support/sqlite/migrations"])

_ = Ecto.Migrator.run(Lotus.Test.Repo, pg_path, :up, all: true, log: false)
_ = Ecto.Migrator.run(Lotus.Test.SqliteRepo, sq_path, :up, all: true, log: false)

Ecto.Adapters.SQL.Sandbox.mode(Lotus.Test.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Lotus.Test.SqliteRepo, :manual)

ExUnit.start(assert_receive_timeout: 500, refute_receive_timeout: 50, exclude: [:skip])
