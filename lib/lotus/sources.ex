defmodule Lotus.Sources do
  @moduledoc false

  alias Lotus.Config

  @doc """
  Normalize to `{repo_module, repo_name_string}`.

  Accepts:
    * `repo_opt` — configured name (string) or repo module (atom) or nil
    * `q_repo`   — query's stored repo (string or module) or nil

  Falls back to Config.default_data_repo/0.
  """
  @spec resolve!(nil | String.t() | module(), nil | String.t() | module()) ::
          {module(), String.t()}
  def resolve!(repo_opt, q_repo) do
    cond do
      is_binary(repo_opt) ->
        {Config.get_data_repo!(repo_opt), repo_opt}

      repo_module?(repo_opt) ->
        {repo_opt, name_from_module!(repo_opt)}

      is_binary(q_repo) ->
        {Config.get_data_repo!(q_repo), q_repo}

      repo_module?(q_repo) ->
        {q_repo, name_from_module!(q_repo)}

      true ->
        {name, mod} = Config.default_data_repo()
        {mod, name}
    end
  end

  @doc """
  Look up the configured *name* for a repo module, or raise if not configured.
  """
  @spec name_from_module!(module()) :: String.t()
  def name_from_module!(mod) do
    case Enum.find(Config.data_repos(), fn {_name, m} -> m == mod end) do
      {name, _} ->
        name

      nil ->
        raise ArgumentError,
              "Repo module #{inspect(mod)} isn’t in :lotus, :data_repos. " <>
                "Configured names: #{inspect(Map.keys(Config.data_repos()))}"
    end
  end

  defp repo_module?(mod) when is_atom(mod),
    do: function_exported?(mod, :__adapter__, 0)

  defp repo_module?(_), do: false

  @doc """
  Detect the source type from a repository module or name.
  """
  @spec source_type(module() | String.t()) :: :postgres | :mysql | :sqlite | :sql_server | :other
  def source_type(repo_name) when is_binary(repo_name) do
    repo = Config.get_data_repo!(repo_name)
    source_type(repo)
  end

  def source_type(repo) when is_atom(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      Ecto.Adapters.MyXQL -> :mysql
      Ecto.Adapters.Tds -> :sql_server
      _ -> :other
    end
  end

  @doc """
  Whether a source type supports a specific feature.
  """
  @spec supports_feature?(atom(), atom()) :: boolean()
  def supports_feature?(:postgres, :search_path), do: true
  def supports_feature?(:postgres, :make_interval), do: true
  def supports_feature?(:postgres, :arrays), do: true
  def supports_feature?(:postgres, :json), do: true

  def supports_feature?(:mysql, :search_path), do: false
  def supports_feature?(:mysql, :make_interval), do: false
  def supports_feature?(:mysql, :arrays), do: false
  def supports_feature?(:mysql, :json), do: true

  def supports_feature?(:sqlite, :search_path), do: false
  def supports_feature?(:sqlite, :make_interval), do: false
  def supports_feature?(:sqlite, :arrays), do: false
  def supports_feature?(:sqlite, :json), do: true

  def supports_feature?(:sql_server, :search_path), do: false
  def supports_feature?(:sql_server, :make_interval), do: false
  def supports_feature?(:sql_server, :arrays), do: false
  def supports_feature?(:sql_server, :json), do: false

  def supports_feature?(_, _), do: false
end
