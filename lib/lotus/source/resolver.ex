defmodule Lotus.Source.Resolver do
  @moduledoc """
  Behaviour for resolving named data sources to adapters.

  This is a **supported extension point**. The default implementation
  (`Lotus.Source.Resolvers.Static`) reads from static `data_sources`
  configuration, which is all most applications need. Alternative
  implementations can resolve sources from registries, databases, or
  external services — for example to register sources at runtime, to
  manage per-tenant sources, or to change the set of available sources
  without restarting the application.

  Configure a custom resolver via the `:source_resolver` config key:

      config :lotus,
        source_resolver: MyApp.SourceResolver

  See the [Custom Resolvers guide](custom-resolvers.html) for contracts,
  minimal examples, and testing guidance.
  """

  @callback resolve(
              source_opt :: nil | String.t() | module(),
              fallback :: nil | String.t() | module()
            ) :: {:ok, Lotus.Source.Adapter.t()} | {:error, term()}

  @callback list_sources() :: [Lotus.Source.Adapter.t()]

  @callback get_source!(name :: String.t()) :: Lotus.Source.Adapter.t() | no_return()

  @callback list_source_names() :: [String.t()]

  @callback default_source() :: {String.t(), Lotus.Source.Adapter.t()}
end
