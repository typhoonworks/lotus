defmodule Lotus.Migrations do
  @moduledoc """
  Migration management system for Lotus.

  Handles versioned schema migrations for the Lotus query storage system.
  Dispatches to database-specific migration modules based on the configured adapter.

  ## Usage

  In your application migration:

      defmodule MyApp.Repo.Migrations.CreateLotusQueries do
        use Ecto.Migration

        def up do
          Lotus.Migrations.up()
        end

        def down do
          Lotus.Migrations.down()
        end
      end
  """

  use Ecto.Migration

  @doc """
  Run the up changes for migrations.

  ## Examples

  Run all migrations:

      Lotus.Migrations.up()

  Run migrations in an alternate prefix:

      Lotus.Migrations.up(prefix: "analytics")
  """
  def up(opts \\ []) when is_list(opts) do
    migrator().up(opts)
  end

  @doc """
  Run the down changes for migrations.

  ## Examples

  Run migrations down:

      Lotus.Migrations.down()

  Run migrations in an alternate prefix:

      Lotus.Migrations.down(prefix: "analytics")
  """
  def down(opts \\ []) when is_list(opts) do
    migrator().down(opts)
  end

  @doc """
  Check the latest version the database is migrated to.

  ## Example

      Lotus.Migrations.migrated_version()
  """
  def migrated_version(opts \\ []) when is_list(opts) do
    migrator().migrated_version(opts)
  end

  defp migrator do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres -> Lotus.Migrations.Postgres
      Ecto.Adapters.SQLite3 -> Lotus.Migrations.SQLite
      _ -> raise ArgumentError, "Unsupported database adapter: #{inspect(repo().__adapter__())}"
    end
  end
end
