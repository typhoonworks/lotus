defmodule Lotus.Migrations.SQLite do
  @moduledoc false

  @behaviour Lotus.Migration

  use Ecto.Migration

  @impl Lotus.Migration
  def up(_opts \\ []) do
    create_if_not_exists table(:lotus_queries, primary_key: false) do
      add(:id, :serial, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:statement, :text, null: false)
      add(:variables, :map, null: false, default: "[]")
      add(:data_repo, :string)
      add(:search_path, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))

    create_if_not_exists table(:lotus_query_visualizations, primary_key: false) do
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

    create_if_not_exists(index(:lotus_query_visualizations, [:query_id, :position]))

    create_if_not_exists(
      unique_index(:lotus_query_visualizations, [:query_id, :name],
        name: "lotus_query_visualizations_query_id_name_index"
      )
    )

    :ok
  end

  @impl Lotus.Migration
  def down(_opts \\ []) do
    drop_if_exists(
      index(:lotus_query_visualizations, [:query_id, :name],
        name: "lotus_query_visualizations_query_id_name_index"
      )
    )

    drop_if_exists(index(:lotus_query_visualizations, [:query_id, :position]))
    drop_if_exists(table(:lotus_query_visualizations))

    drop_if_exists(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    drop_if_exists(table(:lotus_queries))

    :ok
  end

  @impl Lotus.Migration
  def migrated_version(_opts), do: 0
end
