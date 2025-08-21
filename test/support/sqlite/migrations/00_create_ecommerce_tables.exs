defmodule Lotus.Test.SqliteRepo.Migrations.CreateEcommerceTables do
  use Ecto.Migration

  def change do
    create table(:products) do
      add(:name, :string, null: false)
      add(:sku, :string, null: false)
      add(:price, :decimal, precision: 10, scale: 2)
      add(:stock_quantity, :integer, default: 0)
      add(:description, :text)
      add(:active, :boolean, default: true)
      timestamps()
    end

    create(unique_index(:products, [:sku]))
    create(index(:products, [:active]))

    create table(:orders) do
      add(:order_number, :string, null: false)
      add(:customer_email, :string, null: false)
      add(:total_amount, :decimal, precision: 10, scale: 2)
      add(:status, :string, default: "pending")
      add(:notes, :text)
      timestamps()
    end

    create(unique_index(:orders, [:order_number]))
    create(index(:orders, [:customer_email]))
    create(index(:orders, [:status]))

    create table(:order_items) do
      add(:order_id, references(:orders, on_delete: :delete_all), null: false)
      add(:product_id, references(:products, on_delete: :restrict), null: false)
      add(:quantity, :integer, null: false)
      add(:unit_price, :decimal, precision: 10, scale: 2)
      timestamps()
    end

    create(index(:order_items, [:order_id]))
    create(index(:order_items, [:product_id]))
  end
end
