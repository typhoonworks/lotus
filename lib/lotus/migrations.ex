defmodule Lotus.Migrations do
  @moduledoc """
  Migration management system for Lotus.

  Handles versioned schema migrations for the Lotus query storage system.
  """

  use Ecto.Migration

  @latest_version 1
  @all_versions [1]
  @queries_table_name "lotus_queries"

  @doc """
  Returns the latest migration version available.
  """
  @spec latest_version() :: pos_integer()
  def latest_version, do: @latest_version

  @doc """
  Migrates the Lotus tables to a specific version.

  ## Parameters
    - `version`: Integer target version, e.g. 1, 2, etc.

  ## Examples

      # In your migration file:
      defmodule MyApp.Repo.Migrations.CreateLotusQueries do
        use Ecto.Migration

        def up do
          Lotus.Migrations.migrate_to_version(1)
        end

        def down do
          Lotus.Migrations.V1.down()
        end
      end
  """
  @spec migrate_to_version(integer()) :: :ok
  def migrate_to_version(to_version) when is_integer(to_version) do
    unless to_version in @all_versions do
      raise ArgumentError,
            "Invalid migration version: #{to_version}. Valid versions: #{inspect(@all_versions)}"
    end

    current_version = get_current_version()

    cond do
      current_version == to_version ->
        :ok

      current_version < to_version ->
        Enum.each((current_version + 1)..to_version, &migrate_up/1)

      current_version > to_version ->
        Enum.each(current_version..(to_version + 1), &migrate_down/1)
    end
  end

  @doc """
  Gets the current migration version from the database.

  Returns 0 if no migrations have been run yet.
  """
  @spec get_current_version() :: integer()
  def get_current_version do
    prefix = "public"

    case table_version_comment(prefix) do
      nil -> 0
      version when is_integer(version) -> version
    end
  end

  defp migrate_up(version) do
    module = Module.concat([Lotus.Migrations, "V#{version}"])
    module.up()
  end

  defp migrate_down(version) do
    module = Module.concat([Lotus.Migrations, "V#{version}"])
    module.down()
  end

  defp table_version_comment(prefix) do
    {:ok, result} =
      Lotus.repo().query("""
      SELECT obj_description(oid)::int
      FROM pg_class
      WHERE relname = '#{@queries_table_name}'
        AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '#{prefix}')
      """)

    case result.rows do
      [[version]] when is_integer(version) -> version
      _ -> nil
    end
  end
end
