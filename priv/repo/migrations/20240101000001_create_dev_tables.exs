defmodule Lotus.Test.Repo.Migrations.CreateDevTables do
  use Ecto.Migration

  def up do
    create table(:users) do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:age, :integer)
      add(:active, :boolean, default: true)
      add(:metadata, :jsonb)
      timestamps()
    end

    create(unique_index(:users, [:email]))
    create(index(:users, [:active]))

    create table(:posts) do
      add(:title, :string, null: false)
      add(:content, :text)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:published, :boolean, default: false)
      add(:view_count, :integer, default: 0)
      add(:tags, {:array, :string}, default: [])
      timestamps()
    end

    create(index(:posts, [:user_id]))
    create(index(:posts, [:published]))

    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()

    drop(index(:posts, [:published]))
    drop(index(:posts, [:user_id]))
    drop(table(:posts))

    drop(index(:users, [:active]))
    drop(unique_index(:users, [:email]))
    drop(table(:users))
  end
end
