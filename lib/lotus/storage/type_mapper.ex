defmodule Lotus.Storage.TypeMapper do
  @moduledoc """
  Maps database column types to Lotus internal types for automatic casting.

  Different databases use different type names for the same logical types.
  This module normalizes those differences into a consistent set of Lotus types
  that can be used for automatic value casting.

  ## Supported Databases

  - **PostgreSQL**: uuid, integer, numeric, date, timestamp, text, boolean, json, etc.
  - **MySQL**: char(36), binary(16), int, decimal, date, datetime, varchar, json, etc.
  - **SQLite**: INTEGER, REAL, TEXT, BLOB, etc. (dynamic typing)

  ## Usage

      # Map PostgreSQL UUID to Lotus type
      TypeMapper.db_type_to_lotus_type("uuid", Lotus.Sources.Postgres)
      # => :uuid

      # Map MySQL UUID storage to Lotus type
      TypeMapper.db_type_to_lotus_type("char(36)", Lotus.Sources.MySQL)
      # => :uuid

      # Get Ecto type for casting
      TypeMapper.lotus_type_to_ecto_type(:uuid)
      # => Ecto.UUID
  """

  alias Lotus.Sources.{MySQL, Postgres, SQLite3}

  @type lotus_type ::
          :uuid
          | :integer
          | :float
          | :decimal
          | :boolean
          | :date
          | :time
          | :datetime
          | :json
          | :binary
          | :text
          | :enum
          | :composite
          | {:array, lotus_type()}

  @doc """
  Convert database-specific type to Lotus internal type.

  Uses source module to determine database flavor and map accordingly.

  ## Examples

      db_type_to_lotus_type("uuid", Lotus.Sources.Postgres)
      # => :uuid

      db_type_to_lotus_type("char(36)", Lotus.Sources.MySQL)
      # => :uuid

      db_type_to_lotus_type("INTEGER", Lotus.Sources.SQLite3)
      # => :integer
  """
  @spec db_type_to_lotus_type(
          db_type :: String.t(),
          source_module :: module()
        ) :: lotus_type()
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def db_type_to_lotus_type(db_type, Postgres) when is_binary(db_type) do
    lowercased = String.downcase(db_type)

    cond do
      # Array types end with []
      String.ends_with?(lowercased, "[]") ->
        base_type = String.replace_suffix(lowercased, "[]", "")
        {:array, db_type_to_lotus_type(base_type, Postgres)}

      # USER-DEFINED types (enums)
      lowercased == "user-defined" ->
        :enum

      # Standard types
      true ->
        case lowercased do
          "uuid" ->
            :uuid

          # Integer types
          "integer" ->
            :integer

          "bigint" ->
            :integer

          "smallint" ->
            :integer

          "serial" ->
            :integer

          "bigserial" ->
            :integer

          # Decimal/numeric types
          "numeric" <> _ ->
            :decimal

          "decimal" <> _ ->
            :decimal

          # Float types
          "real" ->
            :float

          "double precision" ->
            :float

          # Boolean
          "boolean" ->
            :boolean

          # Date/time types
          "date" ->
            :date

          "timestamp" <> _ ->
            :datetime

          "timestamptz" <> _ ->
            :datetime

          "time" <> _ ->
            :time

          # JSON types
          "json" ->
            :json

          "jsonb" ->
            :json

          # Binary
          "bytea" ->
            :binary

          # Default to text
          _ ->
            :text
        end
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def db_type_to_lotus_type(db_type, MySQL) do
    case String.downcase(db_type) do
      # UUID storage formats in MySQL
      # CHAR(36) with dashes: "550e8400-e29b-41d4-a716-446655440000"
      "char(36)" ->
        :uuid

      # CHAR(32) without dashes: "550e8400e29b41d4a716446655440000"
      "char(32)" ->
        :uuid

      # BINARY(16) - raw 16 bytes
      "binary(16)" ->
        :uuid

      # Integer types
      "int" <> _ ->
        :integer

      "bigint" <> _ ->
        :integer

      "smallint" <> _ ->
        :integer

      # MySQL boolean is tinyint(1)
      "tinyint(1)" ->
        :boolean

      "tinyint" <> _ ->
        :integer

      # Decimal/numeric types
      "decimal" <> _ ->
        :decimal

      "numeric" <> _ ->
        :decimal

      # Float types
      "float" <> _ ->
        :float

      "double" <> _ ->
        :float

      # Date/time types
      "date" ->
        :date

      "datetime" <> _ ->
        :datetime

      "timestamp" <> _ ->
        :datetime

      # JSON
      "json" ->
        :json

      # Default to text
      _ ->
        :text
    end
  end

  def db_type_to_lotus_type(db_type, SQLite3) do
    # SQLite has dynamic typing but uses "type affinity"
    case String.upcase(db_type) do
      "INTEGER" ->
        :integer

      "REAL" ->
        :float

      "NUMERIC" ->
        :decimal

      "DATE" ->
        :date

      "DATETIME" ->
        :datetime

      "BLOB" ->
        :binary

      # SQLite stores UUIDs as TEXT (no native UUID type)
      # All other types default to text
      _ ->
        :text
    end
  end

  # Unknown source - default to text for safety
  def db_type_to_lotus_type(_db_type, _source_module), do: :text

  @doc """
  Returns the Ecto type equivalent for a Lotus type.

  Used for casting values via Ecto's type system.

  ## Examples

      lotus_type_to_ecto_type(:uuid)
      # => Ecto.UUID

      lotus_type_to_ecto_type(:integer)
      # => :integer
  """
  @spec lotus_type_to_ecto_type(lotus_type()) :: atom() | {:array, atom()}
  def lotus_type_to_ecto_type({:array, element_type}),
    do: {:array, lotus_type_to_ecto_type(element_type)}

  def lotus_type_to_ecto_type(:uuid), do: Ecto.UUID
  def lotus_type_to_ecto_type(:integer), do: :integer
  def lotus_type_to_ecto_type(:float), do: :float
  def lotus_type_to_ecto_type(:decimal), do: :decimal
  def lotus_type_to_ecto_type(:boolean), do: :boolean
  def lotus_type_to_ecto_type(:date), do: :date
  def lotus_type_to_ecto_type(:time), do: :time
  def lotus_type_to_ecto_type(:datetime), do: :naive_datetime
  def lotus_type_to_ecto_type(:json), do: :map
  def lotus_type_to_ecto_type(:binary), do: :binary
  def lotus_type_to_ecto_type(:text), do: :string
  def lotus_type_to_ecto_type(:enum), do: :string
  def lotus_type_to_ecto_type(:composite), do: :map
end
