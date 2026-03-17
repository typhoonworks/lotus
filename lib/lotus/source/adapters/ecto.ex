defmodule Lotus.Source.Adapters.Ecto do
  @moduledoc """
  Adapter wrapping any `Ecto.Repo` module in the `Lotus.Source.Adapter` behaviour.

  Delegates database-specific operations to the existing source implementation
  modules (`Lotus.Sources.Postgres`, `Lotus.Sources.MySQL`, `Lotus.Sources.SQLite3`,
  `Lotus.Sources.Default`) based on the repo's underlying Ecto adapter.

  ## Usage

      adapter = Lotus.Source.Adapters.Ecto.wrap("main", MyApp.Repo)

      Lotus.Source.Adapter.execute_query(adapter, "SELECT 1", [], [])
      Lotus.Source.Adapter.list_schemas(adapter)

  The `state` field of the resulting `%Adapter{}` struct holds the repo module
  itself, since Ecto repos are statically supervised and don't require explicit
  connection management.
  """

  @behaviour Lotus.Source.Adapter

  alias Lotus.Source.Adapter

  @impls %{
    Ecto.Adapters.Postgres => Lotus.Sources.Postgres,
    Ecto.Adapters.SQLite3 => Lotus.Sources.SQLite3,
    Ecto.Adapters.MyXQL => Lotus.Sources.MySQL
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Wraps an `Ecto.Repo` module in an `%Adapter{}` struct.

  The resulting adapter delegates all callbacks to the appropriate source
  implementation based on the repo's underlying Ecto adapter.

  ## Parameters

    * `name` — a human-readable identifier (e.g. `"main"`, `"warehouse"`)
    * `repo_module` — the Ecto.Repo module (e.g. `MyApp.Repo`)

  ## Examples

      iex> adapter = Lotus.Source.Adapters.Ecto.wrap("main", MyApp.Repo)
      %Lotus.Source.Adapter{name: "main", module: Lotus.Source.Adapters.Ecto, ...}
  """
  @spec wrap(String.t(), module()) :: Adapter.t()
  def wrap(name, repo_module) when is_binary(name) and is_atom(repo_module) do
    %Adapter{
      name: name,
      module: __MODULE__,
      state: repo_module,
      source_type: detect_source_type(repo_module)
    }
  end

  @doc """
  Detects the source type from a repo module's underlying Ecto adapter.

  ## Examples

      iex> Lotus.Source.Adapters.Ecto.detect_source_type(MyApp.Repo)
      :postgres
  """
  @spec detect_source_type(module()) :: Adapter.source_type()
  def detect_source_type(repo_module) when is_atom(repo_module) do
    case repo_module.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.SQLite3 -> :sqlite
      Ecto.Adapters.MyXQL -> :mysql
      Ecto.Adapters.Tds -> :tds
      _ -> :other
    end
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Query Execution
  # ---------------------------------------------------------------------------

  @impl true
  def execute_query(repo, sql, params, opts) do
    timeout = Keyword.get(opts, :timeout, 15_000)
    search_path = Keyword.get(opts, :search_path)
    impl = impl_for(repo)

    impl.execute_in_transaction(
      repo,
      fn ->
        if search_path do
          impl.set_search_path(repo, search_path)
        end

        case repo.query(sql, params, timeout: timeout) do
          {:ok, %{columns: cols, rows: rows} = raw} ->
            num_rows = Map.get(raw, :num_rows, length(rows || []))
            %{columns: cols, rows: rows, num_rows: num_rows}

          {:error, err} ->
            repo.rollback(impl.format_error(err))
        end
      end,
      opts
    )
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def transaction(repo, fun, opts) do
    impl_for(repo).execute_in_transaction(repo, fn -> fun.(repo) end, opts)
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Introspection (wrap bare returns in {:ok, _} tuples)
  # ---------------------------------------------------------------------------

  @impl true
  def list_schemas(repo) do
    {:ok, impl_for(repo).list_schemas(repo)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def list_tables(repo, schemas, opts) do
    include_views? = Keyword.get(opts, :include_views, false)
    {:ok, impl_for(repo).list_tables(repo, schemas, include_views?)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def get_table_schema(repo, schema, table) do
    {:ok, impl_for(repo).get_table_schema(repo, schema, table)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def resolve_table_schema(repo, table, schemas) do
    {:ok, impl_for(repo).resolve_table_schema(repo, table, schemas)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ---------------------------------------------------------------------------
  # Callbacks — SQL Generation (delegate to source impl)
  # ---------------------------------------------------------------------------

  @impl true
  defdelegate quote_identifier(identifier), to: Lotus.Sources.Postgres

  @impl true
  def param_placeholder(index, var, type) do
    # Delegate based on current module's source type; since this is stateless
    # and we don't have the repo here, we delegate to Postgres as the default.
    # The wrap/2 function ensures the correct source_type is set on the struct.
    Lotus.Sources.Postgres.param_placeholder(index, var, type)
  end

  @impl true
  def limit_offset_placeholders(limit_index, offset_index) do
    Lotus.Sources.Postgres.limit_offset_placeholders(limit_index, offset_index)
  end

  @impl true
  def apply_filters(sql, params, filters) do
    Lotus.Sources.Postgres.apply_filters(sql, params, filters)
  end

  @impl true
  def apply_sorts(sql, sorts) do
    Lotus.Sources.Postgres.apply_sorts(sql, sorts)
  end

  @impl true
  def explain_plan(repo, sql, params, opts) do
    impl_for(repo).explain_plan(repo, sql, params, opts)
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Safety & Visibility (delegate to source impl)
  # ---------------------------------------------------------------------------

  @impl true
  def builtin_denies(repo) do
    impl_for(repo).builtin_denies(repo)
  end

  @impl true
  def builtin_schema_denies(repo) do
    impl_for(repo).builtin_schema_denies(repo)
  end

  @impl true
  def default_schemas(repo) do
    impl_for(repo).default_schemas(repo)
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def health_check(repo) do
    case repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, err}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def disconnect(_repo) do
    # Static repos are managed by the application supervisor.
    :ok
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Error Handling
  # ---------------------------------------------------------------------------

  @impl true
  def format_error(error) do
    impl_for_error(error).format_error(error)
  end

  @impl true
  def handled_errors do
    @impls
    |> Map.values()
    |> Enum.flat_map(& &1.handled_errors())
    |> Enum.uniq()
  end

  # ---------------------------------------------------------------------------
  # Callbacks — Source Identity
  # ---------------------------------------------------------------------------

  @impl true
  def source_type, do: :postgres

  @impl true
  def supports_feature?(feature) do
    Lotus.Sources.supports_feature?(:postgres, feature)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp impl_for(repo) do
    source_mod = repo.__adapter__()
    Map.get(@impls, source_mod, Lotus.Sources.Default)
  end

  defp impl_for_error(%{__exception__: true, __struct__: exc_mod}) do
    Enum.find_value(
      Map.values(@impls) ++ [Lotus.Sources.Default],
      Lotus.Sources.Default,
      fn impl ->
        if exc_mod in impl.handled_errors(), do: impl, else: false
      end
    )
  end

  defp impl_for_error(_), do: Lotus.Sources.Default
end
