defmodule Lotus.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Lotus.Supervisor.start_link([])
  end
end
