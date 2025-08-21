defmodule Lotus.Migration do
  @moduledoc """
  Migration behavior for database-specific migrations.

  Defines the interface that each database adapter's migration module must implement.
  """

  @doc """
  Run the up migrations.
  """
  @callback up(Keyword.t()) :: :ok

  @doc """
  Run the down migrations.
  """
  @callback down(Keyword.t()) :: :ok

  @doc """
  Check the latest version the database is migrated to.
  """
  @callback migrated_version(Keyword.t()) :: non_neg_integer()
end
