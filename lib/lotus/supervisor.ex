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
    Lotus.Config.reload!()

    cache_conf = Keyword.get(opts, :cache, Lotus.Config.cache_config())

    compile_middleware(opts)

    cache_children =
      case cache_conf do
        %{adapter: adapter} -> adapter.spec_config()
        nil -> []
      end

    instance_name = Keyword.get(opts, :name) || Keyword.get(opts, :supervisor_name, Lotus)
    task_sup_name = task_supervisor_name(instance_name)

    children =
      [{Task.Supervisor, name: task_sup_name} | cache_children]

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

  @doc """
  Returns the task supervisor name for the given Lotus instance name.
  """
  def task_supervisor_name(name) when is_atom(name), do: Module.concat(name, TaskSupervisor)
  def task_supervisor_name(name), do: :"lotus_task_sup_#{:erlang.phash2(name)}"

  defp compile_middleware(opts) do
    middleware_conf = Keyword.get(opts, :middleware, Lotus.Config.middleware())
    if is_map(middleware_conf), do: Lotus.Middleware.compile(middleware_conf)
  end
end
