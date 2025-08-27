defmodule Lotus.Test.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :lotus,
    adapter: Ecto.Adapters.Postgres
end

defmodule Lotus.Test.SqliteRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :lotus,
    adapter: Ecto.Adapters.SQLite3
end

defmodule Lotus.Test.MysqlRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :lotus,
    adapter: Ecto.Adapters.MyXQL
end
