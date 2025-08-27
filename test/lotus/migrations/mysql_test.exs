defmodule Lotus.Migrations.MySQLTest do
  use Lotus.Case, async: true

  defmodule MigrationRepo do
    @moduledoc false

    use Ecto.Repo, otp_app: :lotus, adapter: Ecto.Adapters.MyXQL

    alias Lotus.Test.MysqlRepo

    def init(_, _) do
      {:ok, Keyword.put(MysqlRepo.config(), :database, "lotus_migration_test")}
    end
  end

  @moduletag :mysql

  defmodule Migration do
    use Ecto.Migration

    defdelegate up, to: Lotus.Migrations.MySQL
    defdelegate down, to: Lotus.Migrations.MySQL
  end

  test "migrating a mysql database" do
    MigrationRepo.__adapter__().storage_up(MigrationRepo.config())

    start_supervised!(MigrationRepo)

    assert Ecto.Migrator.up(MigrationRepo, 1, Migration) in [:ok, :already_up]
    assert table_exists?("lotus_queries")

    assert :ok = Ecto.Migrator.down(MigrationRepo, 1, Migration)
    refute table_exists?("lotus_queries")
  after
    MigrationRepo.__adapter__().storage_down(MigrationRepo.config())
  end

  defp table_exists?(table_name) do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = 'lotus_migration_test'
      AND TABLE_NAME = '#{table_name}'
    )
    """

    {:ok, %{rows: [[exists]]}} = MigrationRepo.query(query)

    exists != 0
  end
end
