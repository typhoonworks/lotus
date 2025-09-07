defmodule Lotus.Integration.StreamtToCSVTest do
  use Lotus.Case, async: false

  @moduletag :postgres

  alias Lotus.Export
  alias Lotus.Storage.Query
  alias Lotus.Test.Repo
  alias Lotus.Fixtures

  setup do
    u1 = Fixtures.insert_user(%{name: "Stream A", email: "stream_pg_1@example.com"}, Repo)
    u2 = Fixtures.insert_user(%{name: "Stream B", email: "stream_pg_2@example.com"}, Repo)
    u3 = Fixtures.insert_user(%{name: "Stream C", email: "stream_pg_3@example.com"}, Repo)

    on_exit(fn ->
      Repo.delete!(u1)
      Repo.delete!(u2)
      Repo.delete!(u3)
    end)

    :ok
  end

  describe "stream_csv/2 integration (postgres)" do
    test "yields header once and rows across pages" do
      q = %Query{
        statement: """
        SELECT name, email FROM test_users
        WHERE email IN ('stream_pg_1@example.com','stream_pg_2@example.com','stream_pg_3@example.com')
        ORDER BY name
        """,
        variables: [],
        data_repo: nil
      }

      stream = Export.stream_csv(q, repo: "postgres", page_size: 2)

      chunks = Enum.to_list(stream)
      csv = IO.iodata_to_binary(chunks)

      expected = """
      name,email
      Stream A,stream_pg_1@example.com
      Stream B,stream_pg_2@example.com
      Stream C,stream_pg_3@example.com
      """

      assert String.trim(csv) == String.trim(expected)

      # Ensure header appears only once
      assert Enum.count(chunks, fn part -> to_string(part) =~ "name,email" end) == 1
    end
  end
end
