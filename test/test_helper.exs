Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sqlite3)

Lotus.Test.Repo.start_link()
Lotus.Test.SqliteRepo.start_link()

ExUnit.start(assert_receive_timeout: 500, refute_receive_timeout: 50, exclude: [:skip])

Ecto.Adapters.SQL.Sandbox.mode(Lotus.Test.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Lotus.Test.SqliteRepo, :manual)
