defprotocol Lotus.Normalizer do
  @moduledoc """
  Protocol for normalizing raw database values into JSON-safe, displayable forms.

  Lotus applies this protocol to all query result values before they reach
  consumers (UI, exports, API). Implement this protocol for custom database
  types that need special handling.
  """

  @doc "Normalize a value so it is JSON-safe and human-readable."
  @spec normalize(t) :: term()
  def normalize(value)
end

defimpl Lotus.Normalizer, for: Atom do
  def normalize(nil), do: nil
  def normalize(true), do: true
  def normalize(false), do: false
  def normalize(atom), do: to_string(atom)
end

defimpl Lotus.Normalizer, for: BitString do
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

defimpl Lotus.Normalizer, for: Integer do
  def normalize(value), do: value
end

defimpl Lotus.Normalizer, for: Float do
  def normalize(value), do: value
end

defimpl Lotus.Normalizer, for: List do
  def normalize(value) do
    if List.ascii_printable?(value) do
      to_string(value)
    else
      value
    end
  end
end

defimpl Lotus.Normalizer, for: Map do
  def normalize(value), do: value
end

defimpl Lotus.Normalizer, for: Tuple do
  def normalize(value), do: inspect(value)
end

defimpl Lotus.Normalizer, for: Date do
  def normalize(value), do: Date.to_iso8601(value)
end

defimpl Lotus.Normalizer, for: Time do
  def normalize(value), do: Time.to_iso8601(value)
end

defimpl Lotus.Normalizer, for: DateTime do
  def normalize(value), do: DateTime.to_iso8601(value)
end

defimpl Lotus.Normalizer, for: NaiveDateTime do
  def normalize(value), do: NaiveDateTime.to_iso8601(value)
end

defimpl Lotus.Normalizer, for: Decimal do
  def normalize(value) do
    case Decimal.to_string(value) do
      "NaN" -> "NaN"
      "Inf" -> "Infinity"
      "-Inf" -> "-Infinity"
      str -> str
    end
  end
end

defimpl Lotus.Normalizer, for: URI do
  def normalize(value), do: inspect(value)
end

# Fallback for any other type
defimpl Lotus.Normalizer, for: Any do
  def normalize(value), do: inspect(value)
end
