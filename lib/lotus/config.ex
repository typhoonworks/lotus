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
        primary_key_type: :binary_id,  # Defaults to :id
        foreign_key_type: :binary_id,  # Defaults to :id
        unique_names: false,           # Defaults to true

  """

  @type t :: %{
          ecto_repo: module(),
          primary_key_type: :id | :binary_id,
          foreign_key_type: :id | :binary_id,
          unique_names: boolean()
        }

  @schema [
    ecto_repo: [
      type: :atom,
      required: true,
      doc: "The Ecto repository Lotus will use for all DB interactions."
    ],
    primary_key_type: [
      type: {:in, [:id, :binary_id]},
      default: :id,
      doc: "The type for primary keys in Lotus tables."
    ],
    foreign_key_type: [
      type: {:in, [:id, :binary_id]},
      default: :id,
      doc: "The type for foreign keys referencing Lotus tables."
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
    |> Keyword.take([:ecto_repo, :primary_key_type, :foreign_key_type, :unique_names])
  end

  @doc """
  Returns the configured Ecto repository.
  """
  @spec repo!() :: module()
  def repo!, do: load!()[:ecto_repo]

  @doc """
  Returns the configured primary key type (`:id` or `:binary_id`).
  """
  @spec primary_key_type() :: :id | :binary_id
  def primary_key_type, do: load!()[:primary_key_type]

  @doc """
  Returns the configured foreign key type (`:id` or `:binary_id`).
  """
  @spec foreign_key_type() :: :id | :binary_id
  def foreign_key_type, do: load!()[:foreign_key_type]

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
