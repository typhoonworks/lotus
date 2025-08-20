defmodule Lotus.Config do
  @moduledoc """
  Configuration management for Lotus.

  Handles loading and validating configuration from the application environment
  using `NimbleOptions`.

  ## Required Configuration

      config :lotus,
        ecto_repo: MyApp.Repo

  ## Optional Configuration

      config :lotus,
        unique_names: false            # Defaults to true

  """

  @type t :: %{
          ecto_repo: module(),
          unique_names: boolean()
        }

  @schema [
    ecto_repo: [
      type: :atom,
      required: true,
      doc: "The Ecto repository Lotus will use for all DB interactions."
    ],
    unique_names: [
      type: :boolean,
      default: true,
      doc: "Whether to enforce unique query names. Defaults to true."
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
    |> Keyword.take([:ecto_repo, :unique_names])
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
  Returns the entire validated configuration as a map.

  Useful for debugging or inspection.
  """
  @spec all() :: t() | keyword()
  def all, do: load!()
end
