defmodule Lotus.Migrations.MySQL do
  @moduledoc false

  @behaviour Lotus.Migration

  use Ecto.Migration

  @impl Lotus.Migration
  def up(_opts \\ []) do
    create_if_not_exists table(:lotus_queries, primary_key: false) do
      add(:id, :serial, primary_key: true)
      add(:name, :string, size: 255, null: false)
      add(:description, :text)
      add(:statement, :text, null: false)
      add(:variables, :json, null: false, default: fragment("('[]')"))
      add(:data_repo, :string, size: 255)
      add(:search_path, :string, size: 255)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(UTC_TIMESTAMP(6))"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(UTC_TIMESTAMP(6))"))
    end

    create(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))

    create_if_not_exists table(:lotus_query_visualizations, primary_key: false) do
      add(:id, :serial, primary_key: true)

      add(:query_id, references(:lotus_queries, type: :serial, on_delete: :delete_all),
        null: false
      )

      add(:name, :string, size: 255, null: false)
      add(:position, :integer, null: false)
      add(:config, :json, null: false, default: fragment("('{}')"))
      add(:version, :integer, null: false, default: 1)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(UTC_TIMESTAMP(6))"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(UTC_TIMESTAMP(6))"))
    end

    create(index(:lotus_query_visualizations, [:query_id, :position]))

    create(
      unique_index(:lotus_query_visualizations, [:query_id, :name],
        name: "lotus_query_visualizations_query_id_name_index"
      )
    )

    :ok
  end

  @impl Lotus.Migration
  def down(_opts \\ []) do
    drop(table(:lotus_query_visualizations))
    drop(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    drop(table(:lotus_queries))

    :ok
  end

  @impl Lotus.Migration
  def migrated_version(_opts), do: 0
end
