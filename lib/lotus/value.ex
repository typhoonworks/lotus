defmodule Lotus.Value do
  @moduledoc """
  Central value normalization for JSON/CSV/UI display.

  This module provides a unified interface for normalizing database values
  for different output formats while keeping the underlying normalization
  logic centralized in the Export.Value module.
  """

  alias Lotus.Export.Value

  @doc """
  Normalizes a value for JSON export, preserving appropriate types.
  """
  @spec for_json(term()) :: term()
  def for_json(value), do: Value.for_json(value)

  @doc """
  Normalizes a value for CSV export, converting to a string representation.
  """
  @spec to_csv_string(term()) :: String.t()
  def to_csv_string(value), do: Value.to_csv_string(value)

  @doc """
  Normalizes a value for UI display, converting to a readable string representation.
  """
  @spec to_display_string(term()) :: String.t()
  def to_display_string(value), do: Value.to_display_string(value)
end
