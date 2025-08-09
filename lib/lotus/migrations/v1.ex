defmodule Lotus.Migrations.V1 do
  @moduledoc """
  Initial table structure for Lotus queries.

  This migration creates the base `lotus_queries` table with:
  - Configurable primary key type (integer or binary_id)
  - Name, description, query, and tags
  - Timestamps
  - Optional schema prefix
  """

  use Ecto.Migration

  alias Lotus

  @table_name :lotus_queries

  def up(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    table_opts = Keyword.take(opts, [:prefix])

    create table(
             @table_name,
             [primary_key: false] ++ table_opts
           ) do
      case Lotus.Config.primary_key_type() do
        :id ->
          add(:id, :serial, primary_key: true)

        :binary_id ->
          add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      end

      add(:name, :string, null: false)
      add(:description, :text)
      add(:query, :map, null: false)
      add(:tags, {:array, :string}, default: [])

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(@table_name, [:name], name: "lotus_queries_name_index", prefix: prefix))

    # Store the migration version in the table comment
    execute("COMMENT ON TABLE #{prefix}.#{@table_name} IS '1'")
  end

  def down(opts \\ []) do
    drop(table(@table_name, opts))
  end
end
