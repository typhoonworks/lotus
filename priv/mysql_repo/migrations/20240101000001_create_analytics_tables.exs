defmodule Lotus.Test.MysqlRepo.Migrations.CreateAnalyticsTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:user_id, :string, null: false)
      add(:email, :string, null: false)
      add(:signup_source, :string)
      add(:first_login_at, :utc_datetime)
      add(:last_active_at, :utc_datetime)
      add(:is_premium, :boolean, default: false)
      timestamps()
    end

    create(unique_index(:users, [:user_id]))
    create(index(:users, [:email]))
    create(index(:users, [:is_premium]))

    create table(:events) do
      add(:event_id, :string, null: false)
      add(:user_id, :string)
      add(:event_type, :string, null: false)
      add(:properties, :json)
      add(:session_id, :string)
      add(:occurred_at, :utc_datetime, null: false)
      timestamps()
    end

    create(unique_index(:events, [:event_id]))
    create(index(:events, [:user_id]))
    create(index(:events, [:event_type]))
    create(index(:events, [:occurred_at]))

    create table(:page_views) do
      add(:page_url, :string, null: false)
      add(:user_id, :string)
      add(:session_id, :string, null: false)
      add(:referrer, :string)
      add(:user_agent, :text)
      add(:ip_address, :string)
      add(:viewed_at, :utc_datetime, null: false)
      timestamps()
    end

    create(index(:page_views, [:user_id]))
    create(index(:page_views, [:session_id]))
    create(index(:page_views, [:viewed_at]))

    create table(:orders) do
      add(:transaction_id, :string, null: false)
      add(:user_id, :string, null: false)
      add(:product_sku, :string)
      add(:amount_cents, :integer)
      add(:currency, :string, default: "USD")
      add(:payment_method, :string)
      add(:completed_at, :utc_datetime)
      timestamps()
    end

    create(unique_index(:orders, [:transaction_id]))
    create(index(:orders, [:user_id]))
    create(index(:orders, [:completed_at]))

    create table(:api_keys) do
      add(:key_hash, :string, null: false)
      add(:user_id, :string, null: false)
      add(:permissions, :json)
      add(:last_used_at, :utc_datetime)
      add(:expires_at, :utc_datetime)
      timestamps()
    end

    create(unique_index(:api_keys, [:key_hash]))
    create(index(:api_keys, [:user_id]))

    create table(:internal_logs) do
      add(:level, :string, null: false)
      add(:message, :text, null: false)
      add(:context, :json)
      add(:logged_at, :utc_datetime, null: false)
      timestamps()
    end

    create(index(:internal_logs, [:level]))
    create(index(:internal_logs, [:logged_at]))
  end
end
