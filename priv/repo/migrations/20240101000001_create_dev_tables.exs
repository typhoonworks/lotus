defmodule Lotus.Test.Repo.Migrations.CreateDevTables do
  use Ecto.Migration

  def up do
    # Create test data tables
    create table(:test_users) do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:age, :integer)
      add(:active, :boolean, default: true)
      add(:metadata, :jsonb)
      timestamps()
    end

    create(unique_index(:test_users, [:email]))
    create(index(:test_users, [:active]))

    create table(:test_posts) do
      add(:title, :string, null: false)
      add(:content, :text)
      add(:user_id, references(:test_users, on_delete: :delete_all), null: false)
      add(:published, :boolean, default: false)
      add(:view_count, :integer, default: 0)
      add(:tags, {:array, :string}, default: [])
      timestamps()
    end

    create(index(:test_posts, [:user_id]))
    create(index(:test_posts, [:published]))

    # Create Lotus tables
    Lotus.Migrations.up()
  end

  def down do
    # Drop Lotus tables
    Lotus.Migrations.down()

    # Drop test data tables
    drop(index(:test_posts, [:published]))
    drop(index(:test_posts, [:user_id]))
    drop(table(:test_posts))

    drop(index(:test_users, [:active]))
    drop(unique_index(:test_users, [:email]))
    drop(table(:test_users))
  end
end
