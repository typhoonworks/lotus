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

    :ok
  end

  @impl Lotus.Migration
  def down(_opts \\ []) do
    drop(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    drop_if_exists(table(:lotus_queries))

    :ok
  end

  @impl Lotus.Migration
  def migrated_version(_opts), do: 0
end
