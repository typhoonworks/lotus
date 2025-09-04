defmodule Lotus.Storage.QueryVariable.StaticOption do
  @moduledoc """
  Represents a single static option for a QueryVariable select widget.

  Normalizes both simple strings and {value, label} tuples to a consistent format.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @type t :: %__MODULE__{
          value: String.t(),
          label: String.t()
        }

  embedded_schema do
    field(:value, :string)
    field(:label, :string)
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:value, :label])
    |> validate_required([:value, :label])
  end

  @doc """
  Creates a StaticOption from various input formats.

  ## Examples

      iex> StaticOption.from_input("simple")
      %StaticOption{value: "simple", label: "simple"}

      iex> StaticOption.from_input({"val", "Label"})
      %StaticOption{value: "val", label: "Label"}

      iex> StaticOption.from_input(%{"value" => "val", "label" => "Label"})
      %StaticOption{value: "val", label: "Label"}
  """
  def from_input(input) do
    case input do
      # Simple string - value and label are the same
      value when is_binary(value) ->
        %__MODULE__{value: value, label: value}

      # Tuple format - {value, label}
      {value, label} when is_binary(value) and is_binary(label) ->
        %__MODULE__{value: value, label: label}

      # Map format (from JSON/params)
      %{"value" => value, "label" => label} when is_binary(value) and is_binary(label) ->
        %__MODULE__{value: value, label: label}

      %{value: value, label: label} when is_binary(value) and is_binary(label) ->
        %__MODULE__{value: value, label: label}

      _ ->
        nil
    end
  end
end
