defmodule Lotus.Config do
  @moduledoc """
  Configuration management for Lotus.

  Handles loading and validating configuration from the application environment
  using `NimbleOptions`.

  ## Required Configuration

  Lotus requires a storage repository where it will store query definitions:

      config :lotus,
        ecto_repo: MyApp.Repo  # Where Lotus stores its query definitions

  ## Data Repositories Configuration

  Configure named data repositories that Lotus can execute queries against:

      config :lotus,
        data_repos: %{
          "primary" => MyApp.Repo,
          "analytics" => MyApp.AnalyticsRepo,
          "warehouse" => MyApp.WarehouseRepo
        }

  ## Optional Configuration

      config :lotus,
        unique_names: false            # Defaults to true
  """

  @type t :: %{
          ecto_repo: module(),
          unique_names: boolean(),
          data_repos: %{String.t() => module()},
          table_visibility: map()
        }

  @schema [
    ecto_repo: [
      type: :atom,
      required: true,
      doc: "The Ecto repository where Lotus will store its query definitions."
    ],
    data_repos: [
      type: {:map, :string, :atom},
      default: %{},
      doc:
        "Named data repositories that can be used for query execution. Keys are strings, values are repo modules."
    ],
    unique_names: [
      type: :boolean,
      default: true,
      doc: "Whether to enforce unique query names. Defaults to true."
    ],
    table_visibility: [
      type: :map,
      default: %{},
      doc:
        "Configuration for table visibility rules. Controls which tables are accessible through Lotus queries and discovery."
    ]
  ]

  @doc """
  Loads and validates the Lotus configuration.

  Raises `ArgumentError` if the configuration is invalid.
  """
  @spec load!(keyword()) :: t() | keyword()
  def load!(opts \\ get_lotus_config()) do
    case NimbleOptions.validate(opts, @schema) do
      {:ok, conf} -> conf
      {:error, e} -> raise ArgumentError, "Invalid :lotus config: #{Exception.message(e)}"
    end
  end

  defp get_lotus_config do
    Application.get_all_env(:lotus)
    |> Keyword.take([:ecto_repo, :unique_names, :data_repos, :table_visibility])
  end

  @doc """
  Returns the configured Ecto repository.
  """
  @spec repo!() :: module()
  def repo!, do: load!()[:ecto_repo]

  @doc """
  Returns whether unique query names are enforced.
  """
  @spec unique_names?() :: boolean()
  def unique_names?, do: load!()[:unique_names]

  @doc """
  Returns the configured data repositories.
  """
  @spec data_repos() :: %{String.t() => module()}
  def data_repos, do: load!()[:data_repos]

  @doc """
  Gets a data repository by name.

  Returns the repo module or raises if not found.
  """
  @spec get_data_repo!(String.t()) :: module()
  def get_data_repo!(name) do
    case Map.get(data_repos(), name) do
      nil ->
        raise ArgumentError,
              "Data repo '#{name}' not configured. Available repos: #{inspect(Map.keys(data_repos()))}"

      repo ->
        repo
    end
  end

  @doc """
  Lists the names of all configured data repositories.
  """
  @spec list_data_repo_names() :: [String.t()]
  def list_data_repo_names, do: Map.keys(data_repos())

  @doc """
  Returns table visibility rules for a specific repository.

  Falls back to default rules if repo-specific rules are not configured.
  """
  @spec rules_for_repo_name(String.t()) :: keyword()
  def rules_for_repo_name(repo_name) do
    config = load!()
    visibility_config = config[:table_visibility] || %{}

    repo_key = String.to_existing_atom(repo_name)

    # Try repo-specific rules first, then default
    visibility_config[repo_key] || visibility_config[:default] || []
  rescue
    ArgumentError ->
      # If repo_name can't be converted to existing atom, use default
      config = load!()
      visibility_config = config[:table_visibility] || %{}
      visibility_config[:default] || []
  end

  @doc """
  Returns the entire validated configuration as a map.

  Useful for debugging or inspection.
  """
  @spec all() :: t() | keyword()
  def all, do: load!()
end
