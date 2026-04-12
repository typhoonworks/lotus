defmodule Lotus.Source.Adapters.Postgres do
  @moduledoc false

  use Lotus.Source.Adapters.Ecto,
    dialect: Lotus.Source.Adapters.Ecto.Dialects.Postgres
end
