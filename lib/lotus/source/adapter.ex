defmodule Lotus.Source.Adapter do
  @moduledoc """
  Behaviour and struct for database adapters in Lotus.

  An adapter wraps a data source behind a uniform interface. Instead of passing
  raw Ecto.Repo modules throughout the pipeline, consumers work with an
  `%Adapter{}` struct that carries:

    * `name`        — a human-readable identifier (e.g. `"main"`, `"warehouse"`)
    * `module`      — the module implementing this behaviour
    * `state`       — opaque connection state managed by the adapter
    * `source_type` — an atom identifying the database kind (`:postgres`, `:mysql`, etc.)

  ## Implementing an adapter

  Define a module that uses `@behaviour Lotus.Source.Adapter` and implements all
  required callbacks. Callbacks fall into several groups:

    * **Query execution** — `execute_query/4`, `transaction/3`
    * **Introspection** — `list_schemas/1`, `list_tables/3`, `get_table_schema/3`,
      `resolve_table_schema/3`
    * **SQL generation** — `quote_identifier/1`, `param_placeholder/3`,
      `limit_offset_placeholders/2`, `apply_filters/3`, `apply_sorts/2`,
      `explain_plan/4`
    * **Safety & visibility** — `builtin_denies/1`, `builtin_schema_denies/1`,
      `default_schemas/1`
    * **Lifecycle** — `health_check/1`, `disconnect/1`
    * **Error handling** — `format_error/1`, `handled_errors/0`
    * **Source identity** — `source_type/0`, `supports_feature?/1`

  Introspection callbacks consistently return `{:ok, result} | {:error, reason}`
  tuples so callers can handle failures uniformly.

  ## Dispatch helpers

  This module provides convenience functions that accept an `%Adapter{}` struct
  and delegate to the underlying module, passing `state` where needed:

      adapter = %Adapter{name: "main", module: MyPostgres, state: conn, source_type: :postgres}

      Adapter.execute_query(adapter, "SELECT 1", [], [])
      Adapter.list_schemas(adapter)
      Adapter.quote_identifier(adapter, "users")
  """

  @type source_type :: :postgres | :mysql | :sqlite | :other | atom()

  @type column_def :: %{
          name: String.t(),
          type: String.t(),
          nullable: boolean(),
          default: String.t() | nil,
          primary_key: boolean()
        }

  @type t :: %__MODULE__{
          name: String.t() | nil,
          module: module() | nil,
          state: term(),
          source_type: source_type() | nil
        }

  defstruct [:name, :module, :state, :source_type]

  # ---------------------------------------------------------------------------
  # Callbacks — Query Execution
  # ---------------------------------------------------------------------------

  @doc "Execute a SQL query against the data source."
  @callback execute_query(state :: term(), sql :: String.t(), params :: list(), opts :: keyword()) ::
              {:ok, %{columns: [String.t()], rows: [[term()]], num_rows: non_neg_integer()}}
              | {:error, term()}

  @doc "Execute a function within a transaction."
  @callback transaction(state :: term(), fun :: (term() -> any()), opts :: keyword()) ::
              {:ok, any()} | {:error, any()}

  # ---------------------------------------------------------------------------
  # Callbacks — Introspection
  # ---------------------------------------------------------------------------

  @doc "List all schemas in the data source."
  @callback list_schemas(state :: term()) :: {:ok, [String.t()]} | {:error, term()}

  @doc "List tables (and optionally views) in the given schemas."
  @callback list_tables(state :: term(), schemas :: [String.t()], opts :: keyword()) ::
              {:ok, [{schema :: String.t() | nil, table :: String.t()}]} | {:error, term()}

  @doc "Return column definitions for a specific table."
  @callback get_table_schema(state :: term(), schema :: String.t() | nil, table :: String.t()) ::
              {:ok, [column_def()]} | {:error, term()}

  @doc "Resolve which schema contains the named table."
  @callback resolve_table_schema(state :: term(), table :: String.t(), schemas :: [String.t()]) ::
              {:ok, String.t() | nil} | {:error, term()}

  # ---------------------------------------------------------------------------
  # Callbacks — SQL Generation
  # ---------------------------------------------------------------------------

  @doc "Quote a SQL identifier (column, table, schema name) using source-specific syntax."
  @callback quote_identifier(state :: term(), String.t()) :: String.t()

  @doc "Return the parameter placeholder for a variable at the given 1-based index."
  @callback param_placeholder(
              state :: term(),
              index :: pos_integer(),
              var :: String.t(),
              type :: atom() | nil
            ) ::
              String.t()

  @doc "Return `{limit_placeholder, offset_placeholder}` for LIMIT/OFFSET clauses."
  @callback limit_offset_placeholders(state :: term(), pos_integer(), pos_integer()) ::
              {String.t(), String.t()}

  @doc "Append WHERE clauses for the given filters, returning `{sql, params}`."
  @callback apply_filters(state :: term(), sql :: String.t(), params :: list(), filters :: list()) ::
              {String.t(), list()}

  @doc "Append ORDER BY clauses for the given sorts."
  @callback apply_sorts(state :: term(), sql :: String.t(), sorts :: list()) :: String.t()

  @doc "Return the execution plan for a SQL query."
  @callback explain_plan(state :: term(), sql :: String.t(), params :: list(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  # ---------------------------------------------------------------------------
  # Callbacks — Safety & Visibility
  # ---------------------------------------------------------------------------

  @doc "Return built-in deny rules for system tables (list of `{schema_pattern, table_pattern}` tuples)."
  @callback builtin_denies(state :: term()) ::
              [{String.t() | nil | Regex.t(), String.t() | Regex.t()}]

  @doc "Return schema patterns that should be hidden from schema listings."
  @callback builtin_schema_denies(state :: term()) :: [String.t() | Regex.t()]

  @doc "Return the default schemas when none are configured."
  @callback default_schemas(state :: term()) :: [String.t()]

  # ---------------------------------------------------------------------------
  # Callbacks — Lifecycle
  # ---------------------------------------------------------------------------

  @doc "Check that the data source is reachable."
  @callback health_check(state :: term()) :: :ok | {:error, term()}

  @doc "Disconnect from the data source and release resources."
  @callback disconnect(state :: term()) :: :ok

  # ---------------------------------------------------------------------------
  # Callbacks — Error Handling
  # ---------------------------------------------------------------------------

  @doc "Format a database error into a human-readable string."
  @callback format_error(state :: term(), any()) :: String.t()

  @doc "Return the exception modules this adapter knows how to format."
  @callback handled_errors(state :: term()) :: [module()]

  # ---------------------------------------------------------------------------
  # Callbacks — Source Identity
  # ---------------------------------------------------------------------------

  @doc "Return the source type atom (e.g. `:postgres`, `:mysql`)."
  @callback source_type(state :: term()) :: source_type()

  @doc "Whether this adapter supports a given feature."
  @callback supports_feature?(state :: term(), atom()) :: boolean()

  # ---------------------------------------------------------------------------
  # Dispatch helpers — stateful (pass adapter.state as first arg)
  # ---------------------------------------------------------------------------

  @doc "Execute a SQL query via the adapter."
  @spec execute_query(t(), String.t(), list(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_query(%__MODULE__{module: mod, state: state}, sql, params, opts) do
    mod.execute_query(state, sql, params, opts)
  end

  @doc "Execute a function within a transaction via the adapter."
  @spec transaction(t(), (term() -> any()), keyword()) :: {:ok, any()} | {:error, any()}
  def transaction(%__MODULE__{module: mod, state: state}, fun, opts) do
    mod.transaction(state, fun, opts)
  end

  @doc "List all schemas via the adapter."
  @spec list_schemas(t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_schemas(%__MODULE__{module: mod, state: state}) do
    mod.list_schemas(state)
  end

  @doc "List tables via the adapter."
  @spec list_tables(t(), [String.t()], keyword()) ::
          {:ok, [{String.t() | nil, String.t()}]} | {:error, term()}
  def list_tables(%__MODULE__{module: mod, state: state}, schemas, opts) do
    mod.list_tables(state, schemas, opts)
  end

  @doc "Get column definitions for a table via the adapter."
  @spec get_table_schema(t(), String.t() | nil, String.t()) ::
          {:ok, [column_def()]} | {:error, term()}
  def get_table_schema(%__MODULE__{module: mod, state: state}, schema, table) do
    mod.get_table_schema(state, schema, table)
  end

  @doc "Resolve which schema contains a table via the adapter."
  @spec resolve_table_schema(t(), String.t(), [String.t()]) ::
          {:ok, String.t() | nil} | {:error, term()}
  def resolve_table_schema(%__MODULE__{module: mod, state: state}, table, schemas) do
    mod.resolve_table_schema(state, table, schemas)
  end

  @doc "Get the execution plan for a query via the adapter."
  @spec explain_plan(t(), String.t(), list(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def explain_plan(%__MODULE__{module: mod, state: state}, sql, params, opts) do
    mod.explain_plan(state, sql, params, opts)
  end

  @doc "Return built-in deny rules via the adapter."
  @spec builtin_denies(t()) :: [{String.t() | nil | Regex.t(), String.t() | Regex.t()}]
  def builtin_denies(%__MODULE__{module: mod, state: state}) do
    mod.builtin_denies(state)
  end

  @doc "Return built-in schema denies via the adapter."
  @spec builtin_schema_denies(t()) :: [String.t() | Regex.t()]
  def builtin_schema_denies(%__MODULE__{module: mod, state: state}) do
    mod.builtin_schema_denies(state)
  end

  @doc "Return default schemas via the adapter."
  @spec default_schemas(t()) :: [String.t()]
  def default_schemas(%__MODULE__{module: mod, state: state}) do
    mod.default_schemas(state)
  end

  @doc "Check data source health via the adapter."
  @spec health_check(t()) :: :ok | {:error, term()}
  def health_check(%__MODULE__{module: mod, state: state}) do
    mod.health_check(state)
  end

  @doc "Disconnect from the data source via the adapter."
  @spec disconnect(t()) :: :ok
  def disconnect(%__MODULE__{module: mod, state: state}) do
    mod.disconnect(state)
  end

  # ---------------------------------------------------------------------------
  # Dispatch helpers — SQL generation (pass adapter.state for correct dispatch)
  # ---------------------------------------------------------------------------

  @doc "Quote a SQL identifier via the adapter."
  @spec quote_identifier(t(), String.t()) :: String.t()
  def quote_identifier(%__MODULE__{module: mod, state: state}, identifier) do
    mod.quote_identifier(state, identifier)
  end

  @doc "Return the parameter placeholder via the adapter."
  @spec param_placeholder(t(), pos_integer(), String.t(), atom() | nil) :: String.t()
  def param_placeholder(%__MODULE__{module: mod, state: state}, index, var, type) do
    mod.param_placeholder(state, index, var, type)
  end

  @doc "Return LIMIT/OFFSET placeholders via the adapter."
  @spec limit_offset_placeholders(t(), pos_integer(), pos_integer()) :: {String.t(), String.t()}
  def limit_offset_placeholders(%__MODULE__{module: mod, state: state}, limit_index, offset_index) do
    mod.limit_offset_placeholders(state, limit_index, offset_index)
  end

  @doc "Apply filters to a query via the adapter."
  @spec apply_filters(t(), String.t(), list(), list()) :: {String.t(), list()}
  def apply_filters(%__MODULE__{module: mod, state: state}, sql, params, filters) do
    mod.apply_filters(state, sql, params, filters)
  end

  @doc "Apply sorts to a query via the adapter."
  @spec apply_sorts(t(), String.t(), list()) :: String.t()
  def apply_sorts(%__MODULE__{module: mod, state: state}, sql, sorts) do
    mod.apply_sorts(state, sql, sorts)
  end

  @doc "Format an error via the adapter."
  @spec format_error(t(), any()) :: String.t()
  def format_error(%__MODULE__{module: mod, state: state}, error) do
    mod.format_error(state, error)
  end

  @doc "Return handled error modules via the adapter."
  @spec handled_errors(t()) :: [module()]
  def handled_errors(%__MODULE__{module: mod, state: state}) do
    mod.handled_errors(state)
  end

  @doc "Return the source type via the adapter."
  @spec source_type(t()) :: source_type()
  def source_type(%__MODULE__{module: mod, state: state}) do
    mod.source_type(state)
  end

  @doc "Check feature support via the adapter."
  @spec supports_feature?(t(), atom()) :: boolean()
  def supports_feature?(%__MODULE__{module: mod, state: state}, feature) do
    mod.supports_feature?(state, feature)
  end
end
