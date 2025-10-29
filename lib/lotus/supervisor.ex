defmodule Lotus.Supervisor do
  @moduledoc """
  Top-level supervisor for Lotus.
  """

  use Supervisor

  alias Lotus.Cache.Cachex
  alias Lotus.Cache.ETS

  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :supervisor_name) do
      nil -> Supervisor.start_link(__MODULE__, opts)
      sup_name -> Supervisor.start_link(__MODULE__, opts, name: sup_name)
    end
  end

  @impl true
  def init(opts) do
    cache_conf = Keyword.get(opts, :cache, Lotus.Config.cache_config())

    children =
      case cache_conf do
        %{adapter: adapter} when adapter in [ETS, Cachex] -> adapter.spec_config()
        nil -> []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, Lotus),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end
