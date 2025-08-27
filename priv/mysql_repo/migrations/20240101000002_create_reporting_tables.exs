defmodule Lotus.Test.MysqlRepo.Migrations.CreateReportingTables do
  use Ecto.Migration

  def change do
    create table(:monthly_summaries) do
      add(:year, :integer, null: false)
      add(:month, :integer, null: false)
      add(:total_users, :integer, default: 0)
      add(:total_events, :integer, default: 0)
      add(:total_revenue_cents, :bigint, default: 0)
      add(:average_session_duration, :decimal, precision: 10, scale: 2)
      timestamps()
    end

    create(unique_index(:monthly_summaries, [:year, :month]))

    create table(:daily_metrics) do
      add(:date, :date, null: false)
      add(:active_users, :integer, default: 0)
      add(:new_signups, :integer, default: 0)
      add(:page_views, :integer, default: 0)
      add(:bounce_rate, :decimal, precision: 5, scale: 4)
      timestamps()
    end

    create(unique_index(:daily_metrics, [:date]))

    create table(:feature_usage) do
      add(:feature_name, :string, null: false)
      add(:user_id, :string, null: false)
      add(:usage_count, :integer, default: 1)
      add(:first_used_at, :utc_datetime, null: false)
      add(:last_used_at, :utc_datetime, null: false)
      timestamps()
    end

    create(unique_index(:feature_usage, [:feature_name, :user_id]))
    create(index(:feature_usage, [:feature_name]))
    create(index(:feature_usage, [:user_id]))

    create table(:customer_segments) do
      add(:segment_name, :string, null: false)
      add(:criteria, :json, null: false)
      add(:user_count, :integer, default: 0)
      add(:description, :text)
      add(:is_active, :boolean, default: true)
      timestamps()
    end

    create(unique_index(:customer_segments, [:segment_name]))

    create table(:information) do
      add(:info_type, :string, null: false)
      add(:content, :text)
      add(:priority, :integer, default: 0)
      timestamps()
    end

    create(index(:information, [:info_type]))
  end
end
