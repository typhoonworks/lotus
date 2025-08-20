import Config

config :lotus,
  ecto_repo: Lotus.Test.Repo

config :lotus, Lotus.Test.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 2345,
  database: "lotus_dev",
  pool_size: 10,
  priv: "test/support",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true

config :lotus, ecto_repos: [Lotus.Test.Repo]