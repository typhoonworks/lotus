defmodule Lotus.Source.Adapters.SQLite3 do
  @moduledoc false

  use Lotus.Source.Adapters.Ecto,
    dialect: Lotus.Source.Adapters.Ecto.Dialects.SQLite3
end
