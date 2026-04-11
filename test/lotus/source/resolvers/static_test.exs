defmodule Lotus.Source.Resolvers.StaticTest do
  use Lotus.Case, async: true

  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter
  alias Lotus.Source.Resolvers.Static

  describe "resolve/2" do
    test "repo_opt as string finds adapter by name" do
      assert {:ok, adapter} = Static.resolve("postgres", nil)
      assert adapter == EctoAdapter.wrap("postgres", Lotus.Test.Repo)
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "repo_opt as string finds another adapter by name" do
      assert {:ok, adapter} = Static.resolve("sqlite", nil)
      assert adapter == EctoAdapter.wrap("sqlite", Lotus.Test.SqliteRepo)
    end

    test "repo_opt as module finds adapter by reverse lookup" do
      assert {:ok, adapter} = Static.resolve(Lotus.Test.Repo, nil)
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "repo_opt as different module finds adapter by reverse lookup" do
      assert {:ok, adapter} = Static.resolve(Lotus.Test.SqliteRepo, nil)
      assert adapter.name == "sqlite"
      assert adapter.state == Lotus.Test.SqliteRepo
    end

    test "fallback as string finds adapter by name when repo_opt is nil" do
      assert {:ok, adapter} = Static.resolve(nil, "mysql")
      assert adapter.name == "mysql"
      assert adapter.state == Lotus.Test.MysqlRepo
    end

    test "fallback as module finds adapter by reverse lookup when repo_opt is nil" do
      assert {:ok, adapter} = Static.resolve(nil, Lotus.Test.MysqlRepo)
      assert adapter.name == "mysql"
      assert adapter.state == Lotus.Test.MysqlRepo
    end

    test "returns default source when both are nil" do
      assert {:ok, adapter} = Static.resolve(nil, nil)
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "repo_opt string takes precedence over fallback" do
      assert {:ok, adapter} = Static.resolve("sqlite", "mysql")
      assert adapter.name == "sqlite"
    end

    test "repo_opt module takes precedence over fallback string" do
      assert {:ok, adapter} = Static.resolve(Lotus.Test.SqliteRepo, "mysql")
      assert adapter.name == "sqlite"
    end

    test "unknown string name returns error" do
      assert {:error, :not_found} = Static.resolve("unknown", nil)
    end

    test "unknown string fallback returns error when repo_opt is nil" do
      assert {:error, :not_found} = Static.resolve(nil, "nonexistent")
    end

    test "unconfigured module returns error" do
      defmodule UnknownRepo do
        def __adapter__, do: Ecto.Adapters.Postgres
      end

      assert {:error, :not_found} = Static.resolve(UnknownRepo, nil)
    end

    test "non-repo module in repo_opt falls through to fallback" do
      assert {:ok, adapter} = Static.resolve(String, "sqlite")
      assert adapter.name == "sqlite"
    end

    test "non-repo atoms in both positions fall through to default" do
      assert {:ok, adapter} = Static.resolve(String, Enum)
      assert adapter.name == "postgres"
    end

    test "non-atom, non-string values fall through to default" do
      assert {:ok, adapter} = Static.resolve(123, :atom)
      assert adapter.name == "postgres"
    end
  end

  describe "list_sources/0" do
    test "returns all configured repos as adapters" do
      adapters = Static.list_sources()
      names = Enum.map(adapters, & &1.name) |> Enum.sort()

      assert "mysql" in names
      assert "postgres" in names
      assert "sqlite" in names

      Enum.each(adapters, fn adapter ->
        assert %Lotus.Source.Adapter{} = adapter
        assert adapter.module == EctoAdapter
      end)
    end
  end

  describe "get_source!/1" do
    test "returns adapter for configured name" do
      adapter = Static.get_source!("postgres")
      assert adapter.name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end

    test "raises for unknown name" do
      assert_raise ArgumentError, ~r/Data source 'unknown' not configured/, fn ->
        Static.get_source!("unknown")
      end
    end
  end

  describe "list_source_names/0" do
    test "returns name strings" do
      names = Static.list_source_names() |> Enum.sort()
      assert "mysql" in names
      assert "postgres" in names
      assert "sqlite" in names
    end
  end

  describe "default_source/0" do
    test "returns the default as {name, adapter} tuple" do
      {name, adapter} = Static.default_source()
      assert is_binary(name)
      assert %Lotus.Source.Adapter{} = adapter
      assert adapter.name == name
      # Default is "postgres" per test config
      assert name == "postgres"
      assert adapter.state == Lotus.Test.Repo
    end
  end
end
