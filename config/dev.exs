import Config

config :lotus,
  ecto_repo: Lotus.Test.Repo,
  data_repos: %{
    "postgres" => Lotus.Test.Repo,
    "sqlite" => Lotus.Test.SqliteRepo
  }

config :lotus, Lotus.Test.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 2345,
  database: "lotus_dev",
  pool_size: 10,
  priv: "priv/repo",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :lotus, Lotus.Test.SqliteRepo,
  database: Path.expand("../priv/lotus_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 10,
  priv: "priv/sqlite_repo",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :lotus, ecto_repos: [Lotus.Test.Repo, Lotus.Test.SqliteRepo]