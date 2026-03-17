defmodule Lotus.Source.Resolver do
  @moduledoc """
  Behaviour for resolving named data sources to adapters.

  The default implementation reads from static `data_repos` configuration.
  Alternative implementations can resolve sources from registries,
  databases, or external services.
  """

  @callback resolve(
              repo_opt :: nil | String.t() | module(),
              fallback :: nil | String.t() | module()
            ) :: {:ok, Lotus.Source.Adapter.t()} | {:error, term()}

  @callback list_sources() :: [Lotus.Source.Adapter.t()]

  @callback get_source!(name :: String.t()) :: Lotus.Source.Adapter.t() | no_return()

  @callback list_source_names() :: [String.t()]

  @callback default_source() :: {String.t(), Lotus.Source.Adapter.t()}
end
