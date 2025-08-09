Application.ensure_all_started(:postgrex)

Lotus.Test.Repo.start_link()
ExUnit.start(assert_receive_timeout: 500, refute_receive_timeout: 50, exclude: [:skip])
Ecto.Adapters.SQL.Sandbox.mode(Lotus.Test.Repo, :manual)
