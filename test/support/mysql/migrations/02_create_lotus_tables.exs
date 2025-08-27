defmodule Lotus.Test.MysqlRepo.Migrations.CreateLotusTables do
  use Ecto.Migration

  defdelegate up, to: Lotus.Migrations.MySQL
  defdelegate down, to: Lotus.Migrations.MySQL
end
