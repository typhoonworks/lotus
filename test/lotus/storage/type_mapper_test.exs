defmodule Lotus.Storage.TypeMapperTest do
  use Lotus.Case, async: true

  alias Lotus.Sources.{MySQL, Postgres, SQLite3}
  alias Lotus.Storage.TypeMapper

  describe "db_type_to_lotus_type/2 for PostgreSQL" do
    test "maps uuid to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("uuid", Postgres) == :uuid
      assert TypeMapper.db_type_to_lotus_type("UUID", Postgres) == :uuid
    end

    test "maps integer types to :integer" do
      assert TypeMapper.db_type_to_lotus_type("integer", Postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigint", Postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("smallint", Postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("serial", Postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigserial", Postgres) == :integer
    end

    test "maps numeric/decimal types to :decimal" do
      assert TypeMapper.db_type_to_lotus_type("numeric", Postgres) == :decimal
      assert TypeMapper.db_type_to_lotus_type("numeric(10,2)", Postgres) == :decimal
      assert TypeMapper.db_type_to_lotus_type("decimal", Postgres) == :decimal
      assert TypeMapper.db_type_to_lotus_type("decimal(18,4)", Postgres) == :decimal
    end

    test "maps float types to :float" do
      assert TypeMapper.db_type_to_lotus_type("real", Postgres) == :float
      assert TypeMapper.db_type_to_lotus_type("double precision", Postgres) == :float
    end

    test "maps boolean to :boolean" do
      assert TypeMapper.db_type_to_lotus_type("boolean", Postgres) == :boolean
      assert TypeMapper.db_type_to_lotus_type("BOOLEAN", Postgres) == :boolean
    end

    test "maps date to :date" do
      assert TypeMapper.db_type_to_lotus_type("date", Postgres) == :date
    end

    test "maps timestamp types to :datetime" do
      assert TypeMapper.db_type_to_lotus_type("timestamp", Postgres) == :datetime

      assert TypeMapper.db_type_to_lotus_type("timestamp without time zone", Postgres) ==
               :datetime

      assert TypeMapper.db_type_to_lotus_type("timestamp with time zone", Postgres) == :datetime
      assert TypeMapper.db_type_to_lotus_type("timestamptz", Postgres) == :datetime
    end

    test "maps time types to :time" do
      assert TypeMapper.db_type_to_lotus_type("time", Postgres) == :time
      assert TypeMapper.db_type_to_lotus_type("time without time zone", Postgres) == :time
    end

    test "maps json types to :json" do
      assert TypeMapper.db_type_to_lotus_type("json", Postgres) == :json
      assert TypeMapper.db_type_to_lotus_type("jsonb", Postgres) == :json
    end

    test "maps bytea to :binary" do
      assert TypeMapper.db_type_to_lotus_type("bytea", Postgres) == :binary
    end

    test "maps USER-DEFINED to :enum" do
      assert TypeMapper.db_type_to_lotus_type("USER-DEFINED", Postgres) == :enum
      assert TypeMapper.db_type_to_lotus_type("user-defined", Postgres) == :enum
    end

    test "maps array types recursively" do
      assert TypeMapper.db_type_to_lotus_type("integer[]", Postgres) == {:array, :integer}
      assert TypeMapper.db_type_to_lotus_type("uuid[]", Postgres) == {:array, :uuid}
      assert TypeMapper.db_type_to_lotus_type("text[]", Postgres) == {:array, :text}
      assert TypeMapper.db_type_to_lotus_type("boolean[]", Postgres) == {:array, :boolean}
    end

    test "defaults text/varchar to :text" do
      assert TypeMapper.db_type_to_lotus_type("text", Postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("varchar", Postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("character varying", Postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("char", Postgres) == :text
    end

    test "defaults unknown types to :text" do
      assert TypeMapper.db_type_to_lotus_type("custom_type", Postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("unknown", Postgres) == :text
    end
  end

  describe "db_type_to_lotus_type/2 for MySQL" do
    test "maps char(36) to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("char(36)", MySQL) == :uuid
    end

    test "maps char(32) to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("char(32)", MySQL) == :uuid
    end

    test "maps binary(16) to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("binary(16)", MySQL) == :uuid
    end

    test "maps integer types to :integer" do
      assert TypeMapper.db_type_to_lotus_type("int", MySQL) == :integer
      assert TypeMapper.db_type_to_lotus_type("int(11)", MySQL) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigint", MySQL) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigint(20)", MySQL) == :integer
      assert TypeMapper.db_type_to_lotus_type("smallint", MySQL) == :integer
    end

    test "maps tinyint(1) to :boolean" do
      assert TypeMapper.db_type_to_lotus_type("tinyint(1)", MySQL) == :boolean
    end

    test "maps other tinyint to :integer" do
      assert TypeMapper.db_type_to_lotus_type("tinyint", MySQL) == :integer
      assert TypeMapper.db_type_to_lotus_type("tinyint(4)", MySQL) == :integer
    end

    test "maps decimal types to :decimal" do
      assert TypeMapper.db_type_to_lotus_type("decimal", MySQL) == :decimal
      assert TypeMapper.db_type_to_lotus_type("decimal(10,2)", MySQL) == :decimal
      assert TypeMapper.db_type_to_lotus_type("numeric", MySQL) == :decimal
    end

    test "maps float types to :float" do
      assert TypeMapper.db_type_to_lotus_type("float", MySQL) == :float
      assert TypeMapper.db_type_to_lotus_type("double", MySQL) == :float
    end

    test "maps date to :date" do
      assert TypeMapper.db_type_to_lotus_type("date", MySQL) == :date
    end

    test "maps datetime types to :datetime" do
      assert TypeMapper.db_type_to_lotus_type("datetime", MySQL) == :datetime
      assert TypeMapper.db_type_to_lotus_type("timestamp", MySQL) == :datetime
    end

    test "maps json to :json" do
      assert TypeMapper.db_type_to_lotus_type("json", MySQL) == :json
    end

    test "defaults text types to :text" do
      assert TypeMapper.db_type_to_lotus_type("varchar", MySQL) == :text
      assert TypeMapper.db_type_to_lotus_type("varchar(255)", MySQL) == :text
      assert TypeMapper.db_type_to_lotus_type("text", MySQL) == :text
      assert TypeMapper.db_type_to_lotus_type("mediumtext", MySQL) == :text
    end

    test "defaults unknown types to :text" do
      assert TypeMapper.db_type_to_lotus_type("unknown", MySQL) == :text
    end
  end

  describe "db_type_to_lotus_type/2 for SQLite" do
    test "maps INTEGER to :integer" do
      assert TypeMapper.db_type_to_lotus_type("INTEGER", SQLite3) == :integer
      assert TypeMapper.db_type_to_lotus_type("integer", SQLite3) == :integer
    end

    test "maps REAL to :float" do
      assert TypeMapper.db_type_to_lotus_type("REAL", SQLite3) == :float
      assert TypeMapper.db_type_to_lotus_type("real", SQLite3) == :float
    end

    test "maps NUMERIC to :decimal" do
      assert TypeMapper.db_type_to_lotus_type("NUMERIC", SQLite3) == :decimal
    end

    test "maps DATE to :date" do
      assert TypeMapper.db_type_to_lotus_type("DATE", SQLite3) == :date
    end

    test "maps DATETIME to :datetime" do
      assert TypeMapper.db_type_to_lotus_type("DATETIME", SQLite3) == :datetime
    end

    test "maps BLOB to :binary" do
      assert TypeMapper.db_type_to_lotus_type("BLOB", SQLite3) == :binary
    end

    test "defaults TEXT to :text" do
      assert TypeMapper.db_type_to_lotus_type("TEXT", SQLite3) == :text
    end

    test "defaults unknown types to :text" do
      # SQLite stores UUIDs as TEXT
      assert TypeMapper.db_type_to_lotus_type("UUID", SQLite3) == :text
      assert TypeMapper.db_type_to_lotus_type("VARCHAR", SQLite3) == :text
    end
  end

  describe "db_type_to_lotus_type/2 for unknown source" do
    test "defaults to :text for any type" do
      assert TypeMapper.db_type_to_lotus_type("uuid", UnknownSource) == :text
      assert TypeMapper.db_type_to_lotus_type("integer", UnknownSource) == :text
      assert TypeMapper.db_type_to_lotus_type("anything", nil) == :text
    end
  end

  describe "lotus_type_to_ecto_type/1" do
    test "maps :uuid to Ecto.UUID" do
      assert TypeMapper.lotus_type_to_ecto_type(:uuid) == Ecto.UUID
    end

    test "maps :integer to :integer" do
      assert TypeMapper.lotus_type_to_ecto_type(:integer) == :integer
    end

    test "maps :float to :float" do
      assert TypeMapper.lotus_type_to_ecto_type(:float) == :float
    end

    test "maps :decimal to :decimal" do
      assert TypeMapper.lotus_type_to_ecto_type(:decimal) == :decimal
    end

    test "maps :boolean to :boolean" do
      assert TypeMapper.lotus_type_to_ecto_type(:boolean) == :boolean
    end

    test "maps :date to :date" do
      assert TypeMapper.lotus_type_to_ecto_type(:date) == :date
    end

    test "maps :datetime to :naive_datetime" do
      assert TypeMapper.lotus_type_to_ecto_type(:datetime) == :naive_datetime
    end

    test "maps :json to :map" do
      assert TypeMapper.lotus_type_to_ecto_type(:json) == :map
    end

    test "maps :binary to :binary" do
      assert TypeMapper.lotus_type_to_ecto_type(:binary) == :binary
    end

    test "maps :text to :string" do
      assert TypeMapper.lotus_type_to_ecto_type(:text) == :string
    end
  end

  describe "type consistency across databases" do
    @common_concepts [
      {:integer, "integer", "int", "INTEGER"},
      {:float, "real", "float", "REAL"},
      {:decimal, "numeric", "decimal", "NUMERIC"},
      {:date, "date", "date", "DATE"},
      {:datetime, "timestamp", "datetime", "DATETIME"},
      {:json, "json", "json", nil}
    ]

    for {lotus_type, pg_type, mysql_type, sqlite_type} <- @common_concepts, sqlite_type != nil do
      test "#{lotus_type} maps consistently across databases" do
        pg_result = TypeMapper.db_type_to_lotus_type(unquote(pg_type), Postgres)
        mysql_result = TypeMapper.db_type_to_lotus_type(unquote(mysql_type), MySQL)
        sqlite_result = TypeMapper.db_type_to_lotus_type(unquote(sqlite_type), SQLite3)

        assert pg_result == unquote(lotus_type)
        assert mysql_result == unquote(lotus_type)
        assert sqlite_result == unquote(lotus_type)
      end
    end
  end
end
