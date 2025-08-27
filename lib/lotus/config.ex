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
        default_repo: "primary",       # Default data repo for queries
        unique_names: false            # Defaults to true
  """

  @type t :: %{
          ecto_repo: module(),
          unique_names: boolean(),
          data_repos: %{String.t() => module()},
          default_repo: String.t() | nil,
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
    default_repo: [
      type: :string,
      required: false,
      doc:
        "The default data repository name to use when no repo is specified. Required when multiple data_repos are configured."
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
    |> Keyword.take([:ecto_repo, :unique_names, :data_repos, :default_repo, :table_visibility])
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
  Returns the default data repository.

  - If there's only one data repo configured, returns it
  - If multiple repos are configured and default_repo is set, returns that repo
  - If multiple repos are configured without default_repo, raises an error
  - If no data repos are configured, raises an error
  """
  @spec default_data_repo() :: module()
  def default_data_repo do
    repos = data_repos()

    case :maps.size(repos) do
      0 ->
        raise ArgumentError, """
        No data repository available for query execution.

        Please configure at least one data repository:

            config :lotus,
              data_repos: %{
                "primary" => MyApp.Repo
              }
        """

      1 ->
        {_name, repo} = Enum.at(repos, 0)
        repo

      _ ->
        case load!()[:default_repo] do
          nil ->
            raise ArgumentError, """
            Multiple data repositories configured but no default_repo specified.
            Please configure a default_repo:

                config :lotus, default_repo: "primary"

            Available repos: #{inspect(Map.keys(repos))}
            """

          default_name ->
            get_data_repo!(default_name)
        end
    end
  end

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
