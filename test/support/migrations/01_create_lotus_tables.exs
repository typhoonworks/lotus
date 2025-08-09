defmodule Lotus.Test.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration

  import Lotus.Migrations

  def change do
    migrate_to_version(1)
  end
end
