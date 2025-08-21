defmodule Lotus.Repo.Migrations.CreateReportingTestSchema do
  use Ecto.Migration

  def change do
    execute(
      "CREATE SCHEMA IF NOT EXISTS reporting",
      "DROP SCHEMA IF EXISTS reporting CASCADE"
    )

    create table(:customers, prefix: "reporting") do
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:active, :boolean, default: true)
      timestamps()
    end

    create(unique_index(:customers, [:email], prefix: "reporting"))

    create table(:orders, prefix: "reporting") do
      add(:order_number, :string, null: false)

      add(:customer_id, references(:customers, on_delete: :delete_all, prefix: "reporting"),
        null: false
      )

      add(:total_amount, :decimal, precision: 10, scale: 2)
      add(:status, :string, default: "pending")
      timestamps()
    end

    create(unique_index(:orders, [:order_number], prefix: "reporting"))
    create(index(:orders, [:customer_id], prefix: "reporting"))

    execute(
      "COMMENT ON TABLE reporting.customers IS 'BI reporting customers'",
      "COMMENT ON TABLE reporting.customers IS NULL"
    )
  end
end
