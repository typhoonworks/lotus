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

    children =
      case cache_conf do
        nil -> []
        %{adapter: Lotus.Cache.ETS} -> [{Lotus.Cache.ETS, []}]
        %{adapter: Lotus.Cache.Cachex} -> cachex_config(cache_conf)
        %{adapter: _other} -> []
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

  defp cachex_config(cache_conf) do
    Code.ensure_loaded?(Cachex) or
      raise """
      Cachex is not available. Please add {:cachex, "~> 4.0"} to your dependencies.
      """

    cachex_opts = Keyword.get(cache_conf, :cachex_opts, [])

    [{Cachex, [:lotus_cache, cachex_opts]}]
  end
end
