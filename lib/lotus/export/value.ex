defmodule Lotus.Export.Value do
  @moduledoc """
  Value normalization for export formats.
  Handles various database types and edge cases for CSV and JSON export.
  """

  alias Lotus.Normalizer

  @doc """
  Normalizes a value for CSV export, converting to a string representation.
  """
  @spec to_csv_string(term()) :: String.t()
  def to_csv_string(value) do
    value
    |> Normalizer.normalize()
    |> value_to_string()
  end

  @doc """
  Normalizes a value for JSON export, keeping appropriate types.
  """
  @spec for_json(term()) :: term()
  def for_json(value) do
    Normalizer.normalize(value)
  end

  @doc """
  Normalizes a value for display in UI, converting to a readable string representation.
  """
  @spec to_display_string(term()) :: String.t()
  def to_display_string(value) do
    value
    |> Normalizer.normalize()
    |> value_to_string()
  end

  # Convert normalized value to string for CSV
  defp value_to_string(nil), do: ""
  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value) when is_boolean(value), do: to_string(value)
  defp value_to_string(value) when is_number(value), do: to_string(value)
  defp value_to_string(value) when is_atom(value), do: to_string(value)
  defp value_to_string(value) when is_map(value), do: Lotus.JSON.encode!(value)

  defp value_to_string(value) when is_list(value) do
    if List.ascii_printable?(value) do
      to_string(value)
    else
      Lotus.JSON.encode!(value)
    end
  end

  defp value_to_string(value), do: to_string(value)
end
