defmodule Lotus.Storage.TypeCaster do
  @moduledoc """
  Casts variable values to appropriate types based on database column types.

  Automatically converts string values from web UI inputs to the correct database types.
  Provides clear error messages when values cannot be cast to the expected type.

  ## UUID Handling

  For PostgreSQL UUID columns, we must convert string UUIDs to 16-byte binary format.
  Postgrex expects: `<<160,238,188,153,156,11,78,248,187,109,107,185,189,56,10,17>>`

  We use `Ecto.UUID.dump/1` which works for:
  - Standard UUIDs (v4)
  - UUIDv7 (delegates to Ecto.UUID)
  - Any other UUID type that follows RFC 9562 format

  See: https://hexdocs.pm/ecto/Ecto.UUID.html#dump/1

  ## Usage

      # Cast UUID string to binary
      TypeCaster.cast_value("550e8400-e29b-41d4-a716-446655440000", :uuid, %{table: "users", column: "id"})
      # => {:ok, <<85, 14, 132, 0, ...>>}

      # Cast integer string to integer
      TypeCaster.cast_value("42", :integer, %{table: "users", column: "age"})
      # => {:ok, 42}

      # Invalid cast returns error
      TypeCaster.cast_value("not-a-uuid", :uuid, %{table: "users", column: "id"})
      # => {:error, "Failed to cast value for variable bound to users.id..."}
  """

  require Logger

  alias Lotus.Storage.TypeMapper

  @doc """
  Cast a value to match the expected column type.

  First checks for custom type handlers registered via Application config.
  Falls back to built-in type casting if no custom handler is found.

  Returns `{:ok, cast_value}` on success or `{:error, reason}` on failure.

  ## Examples

      cast_value("550e8400-e29b-41d4-a716-446655440000", :uuid, %{table: "users", column: "id"})
      # => {:ok, <<85, 14, 132, ...>>}

      cast_value("42", :integer, %{table: "users", column: "age"})
      # => {:ok, 42}

      cast_value("true", :boolean, %{table: "users", column: "active"})
      # => {:ok, true}

  ## Custom Type Handlers

  You can register custom handlers in your config:

      config :lotus, :type_handlers, %{
        "my_enum" => MyApp.MyEnumHandler
      }

  When a database type name (string) is passed instead of a Lotus type (atom),
  the registry is checked first before mapping to a Lotus type.
  """
  @spec cast_value(
          value :: term(),
          lotus_type :: TypeMapper.lotus_type() | String.t(),
          column_info :: %{column: String.t(), table: String.t()}
        ) :: {:ok, term()} | {:error, String.t()}

  # Handle custom type handlers for database type names (strings)
  def cast_value(value, db_type, column_info) when is_binary(db_type) do
    case get_custom_handler(db_type) do
      {:ok, handler} ->
        handler.cast(value, column_info)

      :not_found ->
        # Map to Lotus type and use built-in casting
        source_module = Map.get(column_info, :source_module)
        lotus_type = TypeMapper.db_type_to_lotus_type(db_type, source_module)
        cast_value(value, lotus_type, column_info)
    end
  end

  def cast_value(value, :uuid, column_info) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid_string} ->
        case Ecto.UUID.dump(uuid_string) do
          {:ok, binary} ->
            {:ok, binary}

          :error ->
            {:error, format_error(:uuid, value, column_info)}
        end

      :error ->
        {:error, format_error(:uuid, value, column_info)}
    end
  end

  def cast_value(value, :integer, column_info) do
    case Integer.parse(to_string(value)) do
      {int, ""} ->
        {:ok, int}

      _ ->
        {:error, format_error(:integer, value, column_info)}
    end
  end

  def cast_value(value, :float, column_info) do
    case Float.parse(to_string(value)) do
      {float, ""} ->
        {:ok, float}

      {_float, _remainder} ->
        {:error, format_error(:float, value, column_info)}

      :error ->
        {:error, format_error(:float, value, column_info)}
    end
  end

  def cast_value(value, :decimal, column_info) do
    case Decimal.parse(to_string(value)) do
      {decimal, _} ->
        {:ok, decimal}

      :error ->
        {:error, format_error(:decimal, value, column_info)}
    end
  rescue
    _e in [ArgumentError, FunctionClauseError] ->
      {:error, format_error(:decimal, value, column_info)}
  end

  def cast_value(value, :boolean, column_info) do
    case value do
      val when val in [true, "true", "1", 1, "yes", "on"] ->
        {:ok, true}

      val when val in [false, "false", "0", 0, "no", "off"] ->
        {:ok, false}

      _ ->
        {:error, format_error(:boolean, value, column_info)}
    end
  end

  def cast_value(value, :date, column_info) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} ->
        {:ok, date}

      {:error, _} ->
        {:error, format_error(:date, value, column_info)}
    end
  end

  def cast_value(value, :time, column_info) do
    case Time.from_iso8601(to_string(value)) do
      {:ok, time} ->
        {:ok, time}

      {:error, _} ->
        {:error, format_error(:time, value, column_info)}
    end
  end

  def cast_value(value, :datetime, column_info) do
    case NaiveDateTime.from_iso8601(to_string(value)) do
      {:ok, datetime} ->
        {:ok, datetime}

      {:error, _} ->
        {:error, format_error(:datetime, value, column_info)}
    end
  end

  def cast_value(value, :json, _column_info) when is_map(value) or is_list(value) do
    {:ok, value}
  end

  def cast_value(value, :json, column_info) when is_binary(value) do
    case Lotus.JSON.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, format_error(:json, value, column_info)}
    end
  end

  def cast_value(value, :binary, column_info) do
    if is_binary(value) do
      {:ok, value}
    else
      {:error, format_error(:binary, value, column_info)}
    end
  end

  def cast_value(value, :text, _column_info) do
    {:ok, to_string(value)}
  end

  def cast_value(value, :enum, _column_info) do
    # Enums are just strings, pass through
    if is_binary(value) do
      {:ok, value}
    else
      {:ok, to_string(value)}
    end
  end

  def cast_value(value, :composite, _column_info) when is_map(value) do
    # Composite types from web come as maps
    {:ok, value}
  end

  def cast_value(value, :composite, column_info) when is_binary(value) do
    case Lotus.JSON.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, format_error(:composite, value, column_info)}
    end
  end

  def cast_value(value, {:array, element_type}, column_info) when is_list(value) do
    # Cast each element
    results =
      Enum.map(value, fn elem ->
        cast_value(elem, element_type, column_info)
      end)

    # Check if all succeeded
    if Enum.all?(results, fn result -> match?({:ok, _}, result) end) do
      casted = Enum.map(results, fn {:ok, val} -> val end)
      {:ok, casted}
    else
      first_error = Enum.find(results, fn result -> match?({:error, _}, result) end)
      first_error
    end
  end

  def cast_value(value, {:array, element_type}, column_info) when is_binary(value) do
    # Handle PostgreSQL array string format: "{1,2,3}"
    case parse_pg_array(value) do
      {:ok, elements} ->
        cast_value(elements, {:array, element_type}, column_info)

      {:error, _reason} ->
        {:error, format_error({:array, element_type}, value, column_info)}
    end
  end

  defp format_error(type, value, _column_info) do
    type_name = format_type_name(type)
    value_str = if is_binary(value), do: "'#{value}'", else: inspect(value)

    "Invalid #{type_name} format: #{value_str} is not a valid #{type_name}#{format_hint(type)}"
  end

  defp format_type_name(:uuid), do: "UUID"
  defp format_type_name(:integer), do: "integer"
  defp format_type_name(:float), do: "float"
  defp format_type_name(:decimal), do: "decimal"
  defp format_type_name(:boolean), do: "boolean"
  defp format_type_name(:date), do: "date"
  defp format_type_name(:time), do: "time"
  defp format_type_name(:datetime), do: "datetime"
  defp format_type_name(:json), do: "JSON"
  defp format_type_name(:binary), do: "binary"
  defp format_type_name(:text), do: "text"
  defp format_type_name(:enum), do: "enum"
  defp format_type_name(:composite), do: "composite"
  defp format_type_name({:array, elem}), do: "array of #{format_type_name(elem)}"
  defp format_type_name(type), do: inspect(type)

  defp format_hint(:uuid), do: " (expected format: 8-4-4-4-12 hex digits)"
  defp format_hint(:date), do: " (expected ISO8601: YYYY-MM-DD)"
  defp format_hint(:time), do: " (expected ISO8601: HH:MM:SS)"
  defp format_hint(:datetime), do: " (expected ISO8601: YYYY-MM-DDTHH:MM:SS)"
  defp format_hint(:boolean), do: " (expected: true/false, yes/no, 1/0, on/off)"
  defp format_hint(:json), do: " (expected valid JSON)"
  defp format_hint({:array, _}), do: " (expected JSON array or PostgreSQL format)"
  defp format_hint(_), do: ""

  defp parse_pg_array(str) do
    trimmed = String.trim(str)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      parse_pg_array_braces(trimmed)
    else
      parse_pg_array_json(str)
    end
  end

  defp parse_pg_array_braces(trimmed) do
    elements =
      trimmed
      |> String.trim_leading("{")
      |> String.trim_trailing("}")
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    {:ok, elements}
  rescue
    _e in [ArgumentError, FunctionClauseError] ->
      {:error, "Invalid array format"}
  end

  defp parse_pg_array_json(str) do
    case Lotus.JSON.decode(str) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, _} -> {:error, "Not an array"}
      {:error, _} -> {:error, "Invalid array format"}
    end
  end

  defp get_custom_handler(db_type) do
    type_handlers = Application.get_env(:lotus, :type_handlers, %{})

    case Map.get(type_handlers, db_type) do
      nil ->
        :not_found

      handler when is_atom(handler) ->
        if function_exported?(handler, :cast, 2) and
             function_exported?(handler, :requires_casting?, 1) do
          {:ok, handler}
        else
          Logger.warning(
            "Type handler #{inspect(handler)} for type #{db_type} does not implement " <>
              "Lotus.Storage.TypeHandler behaviour. Falling back to built-in type mapping."
          )

          :not_found
        end
    end
  end
end
