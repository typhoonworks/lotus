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
      Can be either a list of strings or a list of {value, label} tuples
    * `:options_query`  — SQL to dynamically populate allowed values

  Validation ensures that when a variable is configured as a `:select`
  widget, it must have either `:static_options` or `:options_query`.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Lotus.Storage.QueryVariable.StaticOption

  @primary_key false

  @available_types [:text, :number, :date]
  @available_widgets [:input, :select]

  @type t :: %__MODULE__{
          name: String.t(),
          type: :text | :number | :date,
          widget: :input | :select | nil,
          label: String.t() | nil,
          default: String.t() | nil,
          static_options: [StaticOption.t()],
          options_query: String.t() | nil
        }

  @permitted ~w(name type widget label default options_query)a
  @required ~w(name type)a

  embedded_schema do
    field(:name, :string)
    field(:type, Ecto.Enum, values: @available_types)
    field(:widget, Ecto.Enum, values: @available_widgets)
    field(:label, :string)
    field(:default, :string)
    field(:options_query, :string)

    embeds_many(:static_options, StaticOption)
  end

  def changeset(variable, attrs \\ %{}) do
    variable
    |> cast(attrs, @permitted)
    |> cast_static_options(attrs)
    |> validate_required(@required)
    |> set_default_widget()
    |> validate_select_options()
  end

  defp cast_static_options(changeset, %{static_options: options}) when is_list(options) do
    case validate_consistent_format(options) do
      :ok ->
        normalized_options =
          options
          |> Enum.map(&StaticOption.from_input/1)
          |> Enum.reject(&is_nil/1)

        put_embed(changeset, :static_options, normalized_options)

      {:error, message} ->
        add_error(changeset, :static_options, message)
    end
  end

  defp cast_static_options(changeset, %{"static_options" => options}) when is_list(options) do
    cast_static_options(changeset, %{static_options: options})
  end

  defp cast_static_options(changeset, _attrs), do: changeset

  defp validate_consistent_format(options) do
    has_strings = Enum.any?(options, &is_binary/1)
    has_tuples = Enum.any?(options, &match?({_, _}, &1))
    has_maps = Enum.any?(options, &is_map/1)

    cond do
      has_strings and (has_tuples or has_maps) ->
        {:error, "cannot mix different formats - use consistent format throughout"}

      has_tuples and has_maps ->
        {:error, "cannot mix different formats - use consistent format throughout"}

      true ->
        :ok
    end
  end

  defp set_default_widget(changeset) do
    case {get_field(changeset, :widget), get_field(changeset, :type)} do
      {nil, _} -> put_change(changeset, :widget, :input)
      _ -> changeset
    end
  end

  defp validate_select_options(changeset) do
    case get_field(changeset, :widget) do
      :select -> validate_select_has_options(changeset)
      _ -> changeset
    end
  end

  defp validate_select_has_options(changeset) do
    static_opts = get_field(changeset, :static_options, [])
    query = get_field(changeset, :options_query)

    if (static_opts == [] or is_nil(static_opts)) and is_nil(query) do
      add_error(changeset, :widget, "select must define either static_options or options_query")
    else
      changeset
    end
  end

  @doc """
  Determines the source of options for a query variable.

  Returns `:query` if the variable has a non-empty `options_query`,
  otherwise returns `:static`.

  ## Examples

      iex> var = %Lotus.Storage.QueryVariable{options_query: "SELECT id, name FROM users"}
      iex> Lotus.Storage.QueryVariable.get_option_source(var)
      :query

      iex> var = %Lotus.Storage.QueryVariable{options_query: "   "}
      iex> Lotus.Storage.QueryVariable.get_option_source(var)
      :static

      iex> var = %Lotus.Storage.QueryVariable{static_options: ["a", "b"]}
      iex> Lotus.Storage.QueryVariable.get_option_source(var)
      :static

      iex> var = %Lotus.Storage.QueryVariable{static_options: [{"val", "Label"}]}
      iex> Lotus.Storage.QueryVariable.get_option_source(var)
      :static

  """
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
