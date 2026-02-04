defmodule Lotus.Helpers do
  @moduledoc false

  @doc """
  Recursively converts atom keys to string keys in maps and lists.

  Used to normalize user-provided maps before storing in JSON/map columns
  to ensure consistent key types.
  """
  @spec stringify_keys(term()) :: term()
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  def stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  def stringify_keys(other), do: other

  @doc """
  Escapes special characters in a string for use in SQL LIKE patterns.

  Escapes `%`, `_`, and `\\` which have special meaning in LIKE patterns.
  """
  @spec escape_like(String.t()) :: String.t()
  def escape_like(term) when is_binary(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
