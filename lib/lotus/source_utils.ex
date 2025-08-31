defmodule Lotus.SourceUtils do
  @moduledoc """
  Utility functions for working with data sources and their adapters.
  """

  @doc """
  Detects the source type from a repository module or name.

  ## Examples

      iex> Lotus.SourceUtils.source_type(MyApp.Repo)
      :postgres

      iex> Lotus.SourceUtils.source_type("primary")
      :mysql
  """
  @spec source_type(module() | String.t()) :: :postgres | :mysql | :sqlite | :tds | :other
  def source_type(repo_name) when is_binary(repo_name) do
    repo = Lotus.Config.get_data_repo!(repo_name)
    source_type(repo)
  end

  def source_type(repo) when is_atom(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      Ecto.Adapters.MyXQL -> :mysql
      Ecto.Adapters.Tds -> :tds
      _ -> :other
    end
  end

  @doc """
  Checks if the data source supports a specific feature.

  ## Examples

      iex> Lotus.SourceUtils.supports_feature?(:postgres, :search_path)
      true

      iex> Lotus.SourceUtils.supports_feature?(:sqlite, :search_path)
      false
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

  def supports_feature?(:tds, :search_path), do: false
  def supports_feature?(:tds, :make_interval), do: false
  def supports_feature?(:tds, :arrays), do: false
  def supports_feature?(:tds, :json), do: false

  def supports_feature?(_, _), do: false
end
