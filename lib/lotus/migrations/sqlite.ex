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
      add(:query, :map, null: false)
      add(:tags, :text, default: "[]")
      add(:data_repo, :string)
      add(:search_path, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))

    :ok
  end

  @impl Lotus.Migration
  def down(_opts \\ []) do
    drop_if_exists(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    drop_if_exists(table(:lotus_queries))

    :ok
  end

  @impl Lotus.Migration
  def migrated_version(_opts), do: 0
end
