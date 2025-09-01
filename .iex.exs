# Start the repo when in dev environment
if Mix.env() == :dev do
  {:ok, _} = Lotus.Test.Repo.start_link()
  {:ok, _} = Lotus.Test.SqliteRepo.start_link()
  {:ok, _} = Lotus.Test.MysqlRepo.start_link()
  IO.puts("Started Lotus.Test.Repo for development")
end

# Helpful aliases
alias Lotus.Test.Repo
alias Lotus.Storage
alias Lotus.Storage.Query

# Import Ecto.Query for convenience
import Ecto.Query
