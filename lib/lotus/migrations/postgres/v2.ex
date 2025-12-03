defmodule Lotus.Migrations.Postgres.V2 do
  @moduledoc """
  Add lotus_query_visualizations table for storing chart configs per query.
  """

  use Ecto.Migration

  @table_name :lotus_query_visualizations

  def up(opts \\ %{}) do
    prefix = Map.get(opts, :prefix, "public")
    table_opts = Map.take(opts, [:prefix]) |> Map.to_list()

    create_if_not_exists table(@table_name, [primary_key: false] ++ table_opts) do
      add(:id, :serial, primary_key: true)

      add(:query_id, references(:lotus_queries, type: :integer, on_delete: :delete_all),
        null: false
      )

      add(:name, :string, null: false)
      add(:position, :integer, null: false)
      add(:config, :map, null: false)
      add(:version, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(@table_name, [:query_id, :position], prefix: prefix))

    create_if_not_exists(
      unique_index(@table_name, [:query_id, :name],
        prefix: prefix,
        name: "lotus_query_visualizations_query_id_name_index"
      )
    )
  end

  def down(opts \\ %{}) do
    prefix = Map.get(opts, :prefix, "public")
    table_opts = Map.take(opts, [:prefix]) |> Map.to_list()

    drop_if_exists(
      index(@table_name, [:query_id, :name],
        prefix: prefix,
        name: "lotus_query_visualizations_query_id_name_index"
      )
    )

    drop_if_exists(index(@table_name, [:query_id, :position], prefix: prefix))
    drop_if_exists(table(@table_name, table_opts))
  end
end
