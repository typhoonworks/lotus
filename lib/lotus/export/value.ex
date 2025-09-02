defprotocol Lotus.Export.Normalizer do
  @moduledoc """
  Protocol for normalizing database values for export formats.
  """

  @doc "Normalize a value for export (JSON/CSV-safe)"
  @spec normalize(t) :: term()
  def normalize(value)
end

defmodule Lotus.Export.Value do
  @moduledoc """
  Value normalization for export formats.
  Handles various database types and edge cases for CSV and JSON export.
  """

  alias Lotus.Export.Normalizer

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

defimpl Lotus.Export.Normalizer, for: Atom do
  def normalize(nil), do: nil
  def normalize(true), do: true
  def normalize(false), do: false
  def normalize(atom), do: to_string(atom)
end

defimpl Lotus.Export.Normalizer, for: BitString do
  def normalize(value) when is_binary(value) do
    cond do
      # Check if it's a 16-byte UUID binary
      byte_size(value) == 16 and not String.valid?(value) ->
        case Ecto.UUID.load(value) do
          {:ok, uuid} -> uuid
          :error -> Base.encode64(value)
        end

      # Check if it's valid UTF-8
      String.valid?(value) ->
        value

      # Non-UTF-8 binary data
      true ->
        Base.encode64(value)
    end
  end

  # MySQL BIT fields (non-binary bitstrings)
  def normalize(value) when is_bitstring(value) do
    size = bit_size(value)
    <<int::size(size)>> = value
    to_string(int)
  end
end

defimpl Lotus.Export.Normalizer, for: Integer do
  def normalize(value), do: value
end

defimpl Lotus.Export.Normalizer, for: Float do
  def normalize(value), do: value
end

defimpl Lotus.Export.Normalizer, for: List do
  def normalize(value) do
    if List.ascii_printable?(value) do
      to_string(value)
    else
      value
    end
  end
end

defimpl Lotus.Export.Normalizer, for: Map do
  def normalize(value), do: value
end

defimpl Lotus.Export.Normalizer, for: Tuple do
  def normalize(value), do: inspect(value)
end

defimpl Lotus.Export.Normalizer, for: Date do
  def normalize(value), do: Date.to_iso8601(value)
end

defimpl Lotus.Export.Normalizer, for: Time do
  def normalize(value), do: Time.to_iso8601(value)
end

defimpl Lotus.Export.Normalizer, for: DateTime do
  def normalize(value), do: DateTime.to_iso8601(value)
end

defimpl Lotus.Export.Normalizer, for: NaiveDateTime do
  def normalize(value), do: NaiveDateTime.to_iso8601(value)
end

defimpl Lotus.Export.Normalizer, for: Decimal do
  def normalize(value) do
    case Decimal.to_string(value) do
      "NaN" -> "NaN"
      "Inf" -> "Infinity"
      "-Inf" -> "-Infinity"
      str -> str
    end
  end
end

defimpl Lotus.Export.Normalizer, for: URI do
  def normalize(value), do: inspect(value)
end

# Fallback for any other type
defimpl Lotus.Export.Normalizer, for: Any do
  def normalize(value), do: inspect(value)
end
