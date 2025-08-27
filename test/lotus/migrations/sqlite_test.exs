defmodule Lotus.Migrations.SQLiteTest do
  use Lotus.Case, async: true

  defmodule MigrationRepo do
    @moduledoc false

    use Ecto.Repo, otp_app: :lotus, adapter: Ecto.Adapters.SQLite3

    def init(_, _) do
      test_id = :erlang.unique_integer([:positive])

      {:ok,
       [
         database: "priv/lotus_migration_test_#{test_id}.db",
         pool_size: 1,
         telemetry_prefix: [:lotus, :test, :sqlite_repo]
       ]}
    end
  end

  @moduletag :sqlite

  defmodule Migration do
    use Ecto.Migration

    defdelegate up, to: Lotus.Migrations.SQLite
    defdelegate down, to: Lotus.Migrations.SQLite
  end

  test "migrating a sqlite database" do
    {:ok, _} = start_supervised(MigrationRepo)

    config = MigrationRepo.config()

    _ = MigrationRepo.__adapter__().storage_down(config)

    :ok = MigrationRepo.__adapter__().storage_up(config)

    assert Ecto.Migrator.up(MigrationRepo, 1, Migration) in [:ok, :already_up]
    assert table_exists?("lotus_queries")

    assert :ok = Ecto.Migrator.down(MigrationRepo, 1, Migration)
    refute table_exists?("lotus_queries")
  after
    try do
      _ = MigrationRepo.__adapter__().storage_down(MigrationRepo.config())
    rescue
      _ -> :ok
    end
  end

  defp table_exists?(table_name) do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM sqlite_master
      WHERE type='table'
        AND name='#{table_name}'
    )
    """

    {:ok, %{rows: [[exists]]}} = MigrationRepo.query(query)

    exists != 0
  end
end
