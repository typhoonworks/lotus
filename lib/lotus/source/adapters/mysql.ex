defmodule Lotus.Source.Adapters.MySQL do
  @moduledoc false

  use Lotus.Source.Adapters.Ecto,
    dialect: Lotus.Source.Adapters.Ecto.Dialects.MySQL
end
