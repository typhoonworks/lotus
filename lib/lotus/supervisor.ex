defmodule Lotus.Supervisor do
  @moduledoc """
  Top-level supervisor for Lotus.
  """

  use Supervisor

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

    compile_middleware(opts)

    cache_children =
      case cache_conf do
        %{adapter: adapter} -> adapter.spec_config()
        nil -> []
      end

    children =
      [{Task.Supervisor, name: Lotus.TaskSupervisor} | cache_children]

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

  defp compile_middleware(opts) do
    middleware_conf = Keyword.get(opts, :middleware, Lotus.Config.middleware())
    if is_map(middleware_conf), do: Lotus.Middleware.compile(middleware_conf)
  end
end
