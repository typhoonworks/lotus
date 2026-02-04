defmodule Lotus.Migrations.Postgres.V3 do
  @moduledoc """
  Add dashboard tables for storing dashboard configurations, cards, filters, and mappings.
  """

  use Ecto.Migration

  def up(opts \\ %{}) do
    prefix = Map.get(opts, :prefix, "public")
    table_opts = Map.take(opts, [:prefix]) |> Map.to_list()

    create_if_not_exists table(:lotus_dashboards, [primary_key: false] ++ table_opts) do
      add(:id, :serial, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:settings, :map, null: false, default: %{})
      add(:public_token, :string)
      add(:auto_refresh_seconds, :integer)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      unique_index(:lotus_dashboards, [:name],
        prefix: prefix,
        name: "lotus_dashboards_name_index"
      )
    )

    create_if_not_exists(
      unique_index(:lotus_dashboards, [:public_token],
        prefix: prefix,
        name: "lotus_dashboards_public_token_index",
        where: "public_token IS NOT NULL"
      )
    )

    create_if_not_exists table(:lotus_dashboard_cards, [primary_key: false] ++ table_opts) do
      add(:id, :serial, primary_key: true)

      add(:dashboard_id, references(:lotus_dashboards, type: :integer, on_delete: :delete_all),
        null: false
      )

      add(:query_id, references(:lotus_queries, type: :integer, on_delete: :nilify_all))

      add(:card_type, :string, null: false)
      add(:title, :string)
      add(:visualization_config, :map)
      add(:content, :map, null: false, default: %{})
      add(:position, :integer, null: false)
      add(:layout, :map, null: false, default: %{x: 0, y: 0, w: 6, h: 4})

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      index(:lotus_dashboard_cards, [:dashboard_id, :position], prefix: prefix)
    )

    create_if_not_exists table(:lotus_dashboard_filters, [primary_key: false] ++ table_opts) do
      add(:id, :serial, primary_key: true)

      add(:dashboard_id, references(:lotus_dashboards, type: :integer, on_delete: :delete_all),
        null: false
      )

      add(:name, :string, null: false)
      add(:label, :string, null: false)
      add(:filter_type, :string, null: false)
      add(:widget, :string, null: false)
      add(:default_value, :string)
      add(:config, :map, null: false, default: %{})
      add(:position, :integer, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      index(:lotus_dashboard_filters, [:dashboard_id, :position], prefix: prefix)
    )

    create_if_not_exists(
      unique_index(:lotus_dashboard_filters, [:dashboard_id, :name],
        prefix: prefix,
        name: "lotus_dashboard_filters_dashboard_id_name_index"
      )
    )

    create_if_not_exists table(
                           :lotus_dashboard_card_filter_mappings,
                           [primary_key: false] ++ table_opts
                         ) do
      add(:id, :serial, primary_key: true)

      add(:card_id, references(:lotus_dashboard_cards, type: :integer, on_delete: :delete_all),
        null: false
      )

      add(
        :filter_id,
        references(:lotus_dashboard_filters, type: :integer, on_delete: :delete_all),
        null: false
      )

      add(:variable_name, :string, null: false)
      add(:transform, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:lotus_dashboard_card_filter_mappings, [:card_id], prefix: prefix))

    create_if_not_exists(
      index(:lotus_dashboard_card_filter_mappings, [:filter_id], prefix: prefix)
    )

    create_if_not_exists(
      unique_index(:lotus_dashboard_card_filter_mappings, [:card_id, :filter_id, :variable_name],
        prefix: prefix,
        name: "lotus_dashboard_card_filter_mappings_card_filter_variable_index"
      )
    )
  end

  def down(opts \\ %{}) do
    prefix = Map.get(opts, :prefix, "public")
    table_opts = Map.take(opts, [:prefix]) |> Map.to_list()

    drop_if_exists(
      index(:lotus_dashboard_card_filter_mappings, [:card_id, :filter_id, :variable_name],
        prefix: prefix,
        name: "lotus_dashboard_card_filter_mappings_card_filter_variable_index"
      )
    )

    drop_if_exists(index(:lotus_dashboard_card_filter_mappings, [:filter_id], prefix: prefix))

    drop_if_exists(index(:lotus_dashboard_card_filter_mappings, [:card_id], prefix: prefix))

    drop_if_exists(table(:lotus_dashboard_card_filter_mappings, table_opts))

    drop_if_exists(
      index(:lotus_dashboard_filters, [:dashboard_id, :name],
        prefix: prefix,
        name: "lotus_dashboard_filters_dashboard_id_name_index"
      )
    )

    drop_if_exists(index(:lotus_dashboard_filters, [:dashboard_id, :position], prefix: prefix))

    drop_if_exists(table(:lotus_dashboard_filters, table_opts))

    drop_if_exists(index(:lotus_dashboard_cards, [:dashboard_id, :position], prefix: prefix))

    drop_if_exists(table(:lotus_dashboard_cards, table_opts))

    drop_if_exists(
      index(:lotus_dashboards, [:public_token],
        prefix: prefix,
        name: "lotus_dashboards_public_token_index"
      )
    )

    drop_if_exists(
      index(:lotus_dashboards, [:name],
        prefix: prefix,
        name: "lotus_dashboards_name_index"
      )
    )

    drop_if_exists(table(:lotus_dashboards, table_opts))
  end
end
