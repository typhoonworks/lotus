defmodule Lotus.Storage.TypeMapperTest do
  use Lotus.Case, async: true

  alias Lotus.Storage.TypeMapper

  describe "db_type_to_lotus_type/2 for PostgreSQL" do
    test "maps uuid to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("uuid", :postgres) == :uuid
      assert TypeMapper.db_type_to_lotus_type("UUID", :postgres) == :uuid
    end

    test "maps integer types to :integer" do
      assert TypeMapper.db_type_to_lotus_type("integer", :postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigint", :postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("smallint", :postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("serial", :postgres) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigserial", :postgres) == :integer
    end

    test "maps numeric/decimal types to :decimal" do
      assert TypeMapper.db_type_to_lotus_type("numeric", :postgres) == :decimal
      assert TypeMapper.db_type_to_lotus_type("numeric(10,2)", :postgres) == :decimal
      assert TypeMapper.db_type_to_lotus_type("decimal", :postgres) == :decimal
      assert TypeMapper.db_type_to_lotus_type("decimal(18,4)", :postgres) == :decimal
    end

    test "maps float types to :float" do
      assert TypeMapper.db_type_to_lotus_type("real", :postgres) == :float
      assert TypeMapper.db_type_to_lotus_type("double precision", :postgres) == :float
    end

    test "maps boolean to :boolean" do
      assert TypeMapper.db_type_to_lotus_type("boolean", :postgres) == :boolean
      assert TypeMapper.db_type_to_lotus_type("BOOLEAN", :postgres) == :boolean
    end

    test "maps date to :date" do
      assert TypeMapper.db_type_to_lotus_type("date", :postgres) == :date
    end

    test "maps timestamp types to :datetime" do
      assert TypeMapper.db_type_to_lotus_type("timestamp", :postgres) == :datetime

      assert TypeMapper.db_type_to_lotus_type("timestamp without time zone", :postgres) ==
               :datetime

      assert TypeMapper.db_type_to_lotus_type("timestamp with time zone", :postgres) == :datetime
      assert TypeMapper.db_type_to_lotus_type("timestamptz", :postgres) == :datetime
    end

    test "maps time types to :time" do
      assert TypeMapper.db_type_to_lotus_type("time", :postgres) == :time
      assert TypeMapper.db_type_to_lotus_type("time without time zone", :postgres) == :time
    end

    test "maps json types to :json" do
      assert TypeMapper.db_type_to_lotus_type("json", :postgres) == :json
      assert TypeMapper.db_type_to_lotus_type("jsonb", :postgres) == :json
    end

    test "maps bytea to :binary" do
      assert TypeMapper.db_type_to_lotus_type("bytea", :postgres) == :binary
    end

    test "maps USER-DEFINED to :enum" do
      assert TypeMapper.db_type_to_lotus_type("USER-DEFINED", :postgres) == :enum
      assert TypeMapper.db_type_to_lotus_type("user-defined", :postgres) == :enum
    end

    test "maps array types recursively" do
      assert TypeMapper.db_type_to_lotus_type("integer[]", :postgres) == {:array, :integer}
      assert TypeMapper.db_type_to_lotus_type("uuid[]", :postgres) == {:array, :uuid}
      assert TypeMapper.db_type_to_lotus_type("text[]", :postgres) == {:array, :text}
      assert TypeMapper.db_type_to_lotus_type("boolean[]", :postgres) == {:array, :boolean}
    end

    test "defaults text/varchar to :text" do
      assert TypeMapper.db_type_to_lotus_type("text", :postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("varchar", :postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("character varying", :postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("char", :postgres) == :text
    end

    test "defaults unknown types to :text" do
      assert TypeMapper.db_type_to_lotus_type("custom_type", :postgres) == :text
      assert TypeMapper.db_type_to_lotus_type("unknown", :postgres) == :text
    end
  end

  describe "db_type_to_lotus_type/2 for MySQL" do
    test "maps char(36) to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("char(36)", :mysql) == :uuid
    end

    test "maps char(32) to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("char(32)", :mysql) == :uuid
    end

    test "maps binary(16) to :uuid" do
      assert TypeMapper.db_type_to_lotus_type("binary(16)", :mysql) == :uuid
    end

    test "maps integer types to :integer" do
      assert TypeMapper.db_type_to_lotus_type("int", :mysql) == :integer
      assert TypeMapper.db_type_to_lotus_type("int(11)", :mysql) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigint", :mysql) == :integer
      assert TypeMapper.db_type_to_lotus_type("bigint(20)", :mysql) == :integer
      assert TypeMapper.db_type_to_lotus_type("smallint", :mysql) == :integer
    end

    test "maps tinyint(1) to :boolean" do
      assert TypeMapper.db_type_to_lotus_type("tinyint(1)", :mysql) == :boolean
    end

    test "maps other tinyint to :integer" do
      assert TypeMapper.db_type_to_lotus_type("tinyint", :mysql) == :integer
      assert TypeMapper.db_type_to_lotus_type("tinyint(4)", :mysql) == :integer
    end

    test "maps decimal types to :decimal" do
      assert TypeMapper.db_type_to_lotus_type("decimal", :mysql) == :decimal
      assert TypeMapper.db_type_to_lotus_type("decimal(10,2)", :mysql) == :decimal
      assert TypeMapper.db_type_to_lotus_type("numeric", :mysql) == :decimal
    end

    test "maps float types to :float" do
      assert TypeMapper.db_type_to_lotus_type("float", :mysql) == :float
      assert TypeMapper.db_type_to_lotus_type("double", :mysql) == :float
    end

    test "maps date to :date" do
      assert TypeMapper.db_type_to_lotus_type("date", :mysql) == :date
    end

    test "maps datetime types to :datetime" do
      assert TypeMapper.db_type_to_lotus_type("datetime", :mysql) == :datetime
      assert TypeMapper.db_type_to_lotus_type("timestamp", :mysql) == :datetime
    end

    test "maps json to :json" do
      assert TypeMapper.db_type_to_lotus_type("json", :mysql) == :json
    end

    test "defaults text types to :text" do
      assert TypeMapper.db_type_to_lotus_type("varchar", :mysql) == :text
      assert TypeMapper.db_type_to_lotus_type("varchar(255)", :mysql) == :text
      assert TypeMapper.db_type_to_lotus_type("text", :mysql) == :text
      assert TypeMapper.db_type_to_lotus_type("mediumtext", :mysql) == :text
    end

    test "defaults unknown types to :text" do
      assert TypeMapper.db_type_to_lotus_type("unknown", :mysql) == :text
    end
  end

  describe "db_type_to_lotus_type/2 for SQLite" do
    test "maps INTEGER to :integer" do
      assert TypeMapper.db_type_to_lotus_type("INTEGER", :sqlite) == :integer
      assert TypeMapper.db_type_to_lotus_type("integer", :sqlite) == :integer
    end

    test "maps REAL to :float" do
      assert TypeMapper.db_type_to_lotus_type("REAL", :sqlite) == :float
      assert TypeMapper.db_type_to_lotus_type("real", :sqlite) == :float
    end

    test "maps NUMERIC to :decimal" do
      assert TypeMapper.db_type_to_lotus_type("NUMERIC", :sqlite) == :decimal
    end

    test "maps DATE to :date" do
      assert TypeMapper.db_type_to_lotus_type("DATE", :sqlite) == :date
    end

    test "maps DATETIME to :datetime" do
      assert TypeMapper.db_type_to_lotus_type("DATETIME", :sqlite) == :datetime
    end

    test "maps BLOB to :binary" do
      assert TypeMapper.db_type_to_lotus_type("BLOB", :sqlite) == :binary
    end

    test "defaults TEXT to :text" do
      assert TypeMapper.db_type_to_lotus_type("TEXT", :sqlite) == :text
    end

    test "defaults unknown types to :text" do
      assert TypeMapper.db_type_to_lotus_type("UUID", :sqlite) == :text
      assert TypeMapper.db_type_to_lotus_type("VARCHAR", :sqlite) == :text
    end
  end

  describe "db_type_to_lotus_type/2 for unknown source" do
    test "defaults to :text for any type" do
      assert TypeMapper.db_type_to_lotus_type("uuid", :unknown) == :text
      assert TypeMapper.db_type_to_lotus_type("integer", :unknown) == :text
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
        pg_result = TypeMapper.db_type_to_lotus_type(unquote(pg_type), :postgres)
        mysql_result = TypeMapper.db_type_to_lotus_type(unquote(mysql_type), :mysql)
        sqlite_result = TypeMapper.db_type_to_lotus_type(unquote(sqlite_type), :sqlite)

        assert pg_result == unquote(lotus_type)
        assert mysql_result == unquote(lotus_type)
        assert sqlite_result == unquote(lotus_type)
      end
    end
  end
end
