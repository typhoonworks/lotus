defmodule Lotus.Storage.QueryVariable do
  @moduledoc """
  Represents a variable placeholder (`{{var}}`) used inside a Lotus query.

  Each variable defines:
    * `:name`   — the identifier used in the SQL statement
    * `:type`   — how the value is interpreted (text, number, date)
    * `:widget` — how the value should be collected in the UI (input, select)
    * `:label`  — a human-friendly label shown in the UI
    * `:default` — fallback value if none is provided
    * `:static_options` — hardcoded list of allowed values (for selects)
    * `:options_query`  — SQL to dynamically populate allowed values

  Validation ensures that when a variable is configured as a `:select`
  widget, it must have either `:static_options` or `:options_query`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @available_types [:text, :number, :date]
  @available_widgets [:input, :select]

  @type t :: %__MODULE__{
          name: String.t(),
          type: :text | :number | :date,
          widget: :input | :select | nil,
          label: String.t() | nil,
          default: String.t() | nil,
          static_options: [String.t()],
          options_query: String.t() | nil
        }

  @permitted ~w(name type widget label default static_options options_query)a
  @required ~w(name type)a

  embedded_schema do
    field(:name, :string)
    field(:type, Ecto.Enum, values: @available_types)
    field(:widget, Ecto.Enum, values: @available_widgets)
    field(:label, :string)
    field(:default, :string)
    field(:static_options, {:array, :string}, default: [])
    field(:options_query, :string)
  end

  def changeset(variable, attrs \\ %{}) do
    variable
    |> cast(attrs, @permitted)
    |> validate_required(@required)
    |> set_default_widget()
    |> validate_select_options()
  end

  defp set_default_widget(changeset) do
    case {get_field(changeset, :widget), get_field(changeset, :type)} do
      {nil, _} -> put_change(changeset, :widget, :input)
      _ -> changeset
    end
  end

  defp validate_select_options(changeset) do
    if get_field(changeset, :widget) == :select do
      static_opts = get_field(changeset, :static_options, [])
      query = get_field(changeset, :options_query)

      cond do
        (static_opts == [] or is_nil(static_opts)) and is_nil(query) ->
          add_error(
            changeset,
            :widget,
            "select must define either static_options or options_query"
          )

        true ->
          changeset
      end
    else
      changeset
    end
  end

  @spec get_option_source(t()) :: :query | :static
  def get_option_source(%__MODULE__{options_query: q}) when is_binary(q) do
    if String.trim(q) != "" do
      :query
    else
      :static
    end
  end

  def get_option_source(_), do: :static
end
