defmodule Lotus.Source.Resolvers.StaticTest do
  use Lotus.Case, async: true
  use Mimic

  alias Lotus.Config
  alias Lotus.Source.Resolvers.Static

  describe "resolve/2" do
    test "repo_opt as string finds adapter by name" do
      assert {:ok, adapter} = Static.resolve("postgres", nil)
      assert adapter.name == "postgres"
      assert adapter.module == Lotus.Source.Adapters.Postgres
      assert adapter.state == Lotus.Test.Repo
      assert adapter.source_type == :postgres
    end

    test "repo_opt as string finds another adapter by name" do
      assert {:ok, adapter} = Static.resolve("sqlite", nil)
      assert adapter.name == "sqlite"
      assert adapter.module == Lotus.Source.Adapters.SQLite3
      assert adapter.state == Lotus.Test.SqliteRepo
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

    test "loaded but unconfigured module in repo_opt returns :not_found" do
      # String is a real loaded module but not in data_sources, so we commit
      # to it and surface the error rather than silently masking with fallback.
      assert {:error, :not_found} = Static.resolve(String, "sqlite")
    end

    test "unloaded atom in repo_opt falls through to fallback" do
      # :typoed_name isn't a loaded module — caller probably typo'd a source
      # name. Fall through so the query's data_source can recover.
      assert {:ok, adapter} = Static.resolve(:typoed_name, "sqlite")
      assert adapter.name == "sqlite"
    end

    test "unloaded atoms in both positions fall through to default" do
      assert {:ok, adapter} = Static.resolve(:typoed_one, :typoed_two)
      assert adapter.name == "postgres"
    end

    test "non-atom, non-string values fall through to default" do
      assert {:ok, adapter} = Static.resolve(123, :"Elixir.Nonexistent.Module")
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

        assert adapter.module in [
                 Lotus.Source.Adapters.Postgres,
                 Lotus.Source.Adapters.MySQL,
                 Lotus.Source.Adapters.SQLite3
               ]
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
      assert_raise ArgumentError, ~r/Data source \"unknown\" not configured/, fn ->
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

  describe "wrap_entry error handling" do
    setup do
      Mimic.copy(Config)
      :ok
    end

    test "raises ArgumentError with a descriptive message for an unhandled map entry" do
      # Regression: before the fix, a map entry without a matching source_adapter
      # silently fell through to EctoAdapter.wrap/2, which has an
      # `when is_atom/1` guard, and raised FunctionClauseError.
      Config
      |> stub(:data_sources, fn -> %{"api" => %{adapter: :some_http_adapter}} end)
      |> stub(:source_adapters, fn -> [] end)

      assert_raise ArgumentError, ~r/No source adapter can handle data source "api"/, fn ->
        Static.list_sources()
      end
    end

    test "uses a matching custom source_adapter for a map entry" do
      defmodule FakeHttpAdapter do
        def can_handle?(%{adapter: :fake_http}), do: true
        def can_handle?(_), do: false

        def wrap(name, %{adapter: :fake_http} = opts) do
          %Lotus.Source.Adapter{
            name: name,
            module: __MODULE__,
            state: opts,
            source_type: :other
          }
        end
      end

      Config
      |> stub(:data_sources, fn -> %{"api" => %{adapter: :fake_http, url: "x"}} end)
      |> stub(:source_adapters, fn -> [FakeHttpAdapter] end)

      [adapter] = Static.list_sources()
      assert adapter.name == "api"
      assert adapter.module == FakeHttpAdapter
      assert adapter.state == %{adapter: :fake_http, url: "x"}
      assert adapter.source_type == :other
    end
  end
end
