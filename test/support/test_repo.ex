defmodule Lotus.Test.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :lotus,
    adapter: Ecto.Adapters.Postgres
end
