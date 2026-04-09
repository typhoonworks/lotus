defmodule Lotus.Visibility.Resolver do
  @moduledoc """
  Behaviour for resolving visibility rules for a given data source.

  This is a **supported extension point**. The default implementation
  (`Lotus.Visibility.Resolvers.Static`) reads from static application
  configuration, which is all most applications need. Alternative
  implementations can load rules from registries, databases, feature
  flags, or per-tenant configuration — for example to change rules
  without restarting the application, or to scope rules to the current
  user or tenant.

  Configure a custom resolver via the `:visibility_resolver` config key:

      config :lotus,
        visibility_resolver: MyApp.VisibilityResolver

  The rule formats returned by each callback are the same as those
  consumed by the static resolver — see the [Visibility guide](visibility.html)
  for the full syntax, and the [Custom Resolvers guide](custom-resolvers.html)
  for contracts, minimal examples, and testing guidance.
  """

  @callback schema_rules_for(source_name :: String.t()) :: keyword()
  @callback table_rules_for(source_name :: String.t()) :: keyword()
  @callback column_rules_for(source_name :: String.t()) :: list()
end
