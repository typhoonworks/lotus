defmodule Lotus.Test.MysqlRepo.Migrations.CreateTestTables do
  use Ecto.Migration

  def change do
    create table(:test_users) do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:age, :integer)
      add(:active, :boolean, default: true)
      add(:metadata, :json)
      timestamps()
    end

    create(unique_index(:test_users, [:email]))
    create(index(:test_users, [:active]))

    create table(:test_posts) do
      add(:title, :string, null: false)
      add(:content, :text)
      add(:user_id, references(:test_users, on_delete: :restrict), null: false)
      add(:published, :boolean, default: false)
      add(:view_count, :integer, default: 0)
      add(:tags, :json, default: fragment("('[]')"))
      timestamps()
    end

    create(index(:test_posts, [:user_id]))
    create(index(:test_posts, [:published]))
  end
end
