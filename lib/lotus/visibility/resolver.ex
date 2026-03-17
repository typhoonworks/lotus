defmodule Lotus.Visibility.Resolver do
  @moduledoc """
  Behaviour for resolving visibility rules for a given data source.

  The default implementation reads from static application configuration.
  Alternative implementations can load rules from registries or databases.
  """

  @callback schema_rules_for(source_name :: String.t()) :: keyword()
  @callback table_rules_for(source_name :: String.t()) :: keyword()
  @callback column_rules_for(source_name :: String.t()) :: list()
end
