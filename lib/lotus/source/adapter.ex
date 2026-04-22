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
    * **SQL generation** — `quote_identifier/2`, `param_placeholder/4`,
      `limit_offset_placeholders/3`, `explain_plan/4`
    * **Pipeline** — `transform_statement/2`, `transform_bound_query/3`,
      `apply_filters/3`, `apply_sorts/3`, `apply_pagination/3`,
      `needs_preflight?/2`, `sanitize_query/3`, `extract_accessed_resources/2`
    * **Safety & visibility** — `builtin_denies/1`, `builtin_schema_denies/1`,
      `default_schemas/1`
    * **Lifecycle** — `health_check/1`, `disconnect/1`
    * **Error handling** — `format_error/2`, `handled_errors/1`
    * **Source identity** — `source_type/1`, `supports_feature?/2`

  ## Pipeline Statement contract

  All pipeline callbacks operate on a `%Lotus.Query.Statement{}` struct that
  carries the adapter-native payload (`:text`, opaque term), `:params`, and
  adapter-specific `:meta`. Adapters return a new statement with the relevant
  field updated — the pipeline is a series of pure `statement -> statement`
  transforms.

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

  alias Lotus.Query.Statement

  @type source_type :: :postgres | :mysql | :sqlite | :other | atom()

  @type column_def :: %{
          name: String.t(),
          type: String.t(),
          nullable: boolean(),
          default: String.t() | nil,
          primary_key: boolean()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          module: module(),
          state: term(),
          source_type: source_type()
        }

  @enforce_keys [:name, :module, :source_type]
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

  @doc "Apply filters to the statement, returning a new statement with the filters baked in."
  @callback apply_filters(state :: term(), statement :: Statement.t(), filters :: list()) ::
              Statement.t()

  @doc "Apply sorts to the statement, returning a new statement with the sort order baked in."
  @callback apply_sorts(state :: term(), statement :: Statement.t(), sorts :: list()) ::
              Statement.t()

  @doc "Return the execution plan for a SQL query."
  @callback explain_plan(state :: term(), sql :: String.t(), params :: list(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  # ---------------------------------------------------------------------------
  # Callbacks — Pipeline (Query Processing)
  # ---------------------------------------------------------------------------

  @doc """
  Validate that a statement is safe to execute.

  Called before execution to enforce single-statement and deny-list rules.
  Return `:ok` to allow or `{:error, reason}` to block.

  ## Options

    * `:read_only` — when `true`, block write operations

  Default (when not implemented): `:ok` (allow all statements).
  """
  @callback sanitize_query(state :: term(), statement :: Statement.t(), opts :: keyword()) ::
              :ok | {:error, String.t()}

  @doc """
  Rewrite the statement after variable substitution.

  Pipeline position: fires inside `Lotus.execute_with_options/7` **after**
  `{{var}}` placeholders have been resolved into `statement.params`, and
  **before** `apply_filters`, `apply_sorts`, and `apply_pagination` mutate
  the statement.

  Use when you need access to the bound parameter values — for example, to
  inline values into `statement.text` for a transport that can't carry
  prepared-statement parameters, or to apply a transformation that depends on
  the bound values.

  The statement payload is whatever the adapter understands (SQL text, JSON
  DSL, AST, etc.); this callback is language-agnostic. For rewrites that only
  need the raw statement text (before variables are bound), implement
  `transform_statement/2` instead.

  Default (when not implemented): statement unchanged.
  """
  @callback transform_bound_query(
              state :: term(),
              statement :: Statement.t(),
              opts :: keyword()
            ) ::
              Statement.t()

  @doc """
  Extract the set of tables/relations a statement will access.

  Used by `Lotus.Preflight` to check visibility rules before execution.
  Return `{:ok, MapSet}` with `{schema, table}` tuples, `{:error, reason}`,
  or `{:unrestricted, reason}` when visibility cannot be enforced at this
  layer (the adapter signals Lotus to consult the host-app opt-in gate
  before allowing the statement through).

  Default (when not implemented): `{:unrestricted, "adapter does not implement extract_accessed_resources/2"}`.
  """
  @callback extract_accessed_resources(state :: term(), statement :: Statement.t()) ::
              {:ok, MapSet.t({String.t() | nil, String.t()})}
              | {:error, term()}
              | {:unrestricted, String.t()}

  @typedoc """
  Optional count-query description placed in `statement.meta[:count_spec]` by
  `apply_pagination/3` when the caller requested `count: :exact`. Plain data:
  `:query` is the count payload (SQL text, JSON DSL, whatever the adapter's
  language calls "count this result set"), and `:params` are its bound
  parameters. Lotus core runs this through the same adapter the paginated
  statement ran through — the adapter does not need to remember its own
  identity.
  """
  @type count_spec :: %{query: term(), params: list()}

  @doc """
  Rewrite a statement to return a single page of rows, and optionally record
  a count query for the full result set.

  Pipeline position: fires **after** `apply_filters/3` and `apply_sorts/3`,
  so the input statement already has any filters and sorts applied.

  ## Opts

    * `:limit` (required) — page size
    * `:offset` — page offset (default: `0`)
    * `:count` — `:none` (default) or `:exact`. When `:exact`, the adapter
      should place a `count_spec` in `statement.meta[:count_spec]`.
    * `:search_path` — forwarded by callers that care about schema isolation

  ## Return

  A paginated `%Statement{}`. When counting is requested, the returned
  statement's `:meta` map holds `:count_spec` (a `count_spec()` value).
  Lotus core assembles any surrounding metadata (original adapter struct,
  search_path, etc.) from its own scope.

  Default (when not implemented): statement unchanged, no pagination.
  """
  @callback apply_pagination(
              state :: term(),
              statement :: Statement.t(),
              pagination_opts :: keyword()
            ) ::
              Statement.t()

  @doc """
  Whether a statement needs the visibility preflight check before execution.

  Implementors return `false` for read-only introspection statements that do
  not access visible relations (e.g. SQL `EXPLAIN`, `SHOW`, `PRAGMA`) and
  `true` for everything else. Lotus core runs preflight when this callback
  returns `true` and skips it when `false`.

  Default (when not implemented): `true` (always preflight — safer).
  """
  @callback needs_preflight?(state :: term(), statement :: Statement.t()) :: boolean()

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

  @doc "Return the query language identifier for this source (e.g. `\"sql:postgres\"`)."
  @callback query_language(state :: term()) :: String.t()

  @doc "Wrap a statement with a limit clause using source-specific syntax."
  @callback limit_query(state :: term(), statement :: String.t(), limit :: pos_integer()) ::
              String.t()

  @doc ~S'Return the human-readable label for the top-level hierarchy (e.g. "Tables", "Indices").'
  @callback hierarchy_label(state :: term()) :: String.t()

  @doc "Return an example query string for placeholder text in the query editor."
  @callback example_query(state :: term(), table :: String.t(), schema :: String.t() | nil) ::
              String.t()

  # ---------------------------------------------------------------------------
  # Callbacks — Pluggable Registration
  # ---------------------------------------------------------------------------

  @doc "Whether this adapter can handle the given data source entry (e.g. a repo module)."
  @callback can_handle?(term()) :: boolean()

  @doc "Wrap a raw data source entry into an `%Adapter{}` struct."
  @callback wrap(name :: String.t(), term()) :: t()

  # ---------------------------------------------------------------------------
  # Callbacks — Query Transformation & Type Mapping
  # ---------------------------------------------------------------------------

  @doc """
  Rewrite the statement before variables are extracted and bound.

  Pipeline position: fires inside `Lotus.Storage.Query.to_sql_params/2`
  **before** `{{var}}` placeholders are extracted from `statement.text` and
  before any value is bound. The statement's `:params` is `[]` at this point.

  Use for language-specific syntax normalization of the stored template
  (e.g., wildcard rewriting, quoted-variable stripping). Works for any
  query language: SQL text, JSON DSL, Cypher, etc.

  For rewrites that need access to the resolved param values (post-binding),
  implement `transform_bound_query/3` instead.

  Default (when not implemented): statement unchanged.
  """
  @callback transform_statement(state :: term(), statement :: Statement.t()) :: Statement.t()

  @doc "Map a database column type string to a Lotus internal type atom."
  @callback db_type_to_lotus_type(state :: term(), db_type :: String.t()) :: atom()

  @doc "Return editor configuration (keywords, types, functions) for the adapter."
  @callback editor_config(state :: term()) :: %{
              language: String.t(),
              keywords: [String.t()],
              types: [String.t()],
              functions: [%{name: String.t(), detail: String.t(), args: String.t()}],
              context_boundaries: [String.t()]
            }

  @optional_callbacks [
    sanitize_query: 3,
    transform_bound_query: 3,
    extract_accessed_resources: 2,
    apply_pagination: 3,
    needs_preflight?: 2,
    query_language: 1,
    hierarchy_label: 1,
    example_query: 3,
    can_handle?: 1,
    wrap: 2,
    transform_statement: 2
  ]

  # Conservative fallback deny rules applied when no adapter can be resolved
  # for a source name (e.g., typo'd repo, unconfigured source). Owned here so
  # generic cross-cutting modules like `Lotus.Visibility` don't need to reach
  # into the Ecto subtree for a sensible default. Built-in Ecto dialects
  # (Postgres, MySQL, SQLite) override these via their own callbacks.
  @fallback_table_denies [
    {"pg_catalog", ~r/.*/},
    {"information_schema", ~r/.*/},
    {nil, ~r/^sqlite_/},
    {nil, "schema_migrations"},
    {"public", "schema_migrations"},
    {"public", "lotus_queries"},
    {nil, "lotus_queries"},
    {"public", "lotus_query_visualizations"},
    {nil, "lotus_query_visualizations"},
    {"public", "lotus_dashboards"},
    {nil, "lotus_dashboards"},
    {"public", "lotus_dashboard_cards"},
    {nil, "lotus_dashboard_cards"},
    {"public", "lotus_dashboard_filters"},
    {nil, "lotus_dashboard_filters"},
    {"public", "lotus_dashboard_card_filter_mappings"},
    {nil, "lotus_dashboard_card_filter_mappings"}
  ]

  @fallback_schema_denies [
    "pg_catalog",
    "information_schema",
    "mysql",
    "performance_schema",
    "sys"
  ]

  @doc """
  Built-in table-level deny rules to apply when no adapter can be resolved.

  Returns a conservative shotgun-union list covering Postgres, MySQL, and
  SQLite system-schema patterns plus Lotus's own storage tables. Callers with
  an `%Adapter{}` struct should prefer `builtin_denies/1` (the struct dispatch
  helper), which routes to the adapter's own rules.
  """
  @spec builtin_denies() :: [{String.t() | nil | Regex.t(), String.t() | Regex.t()}]
  def builtin_denies, do: @fallback_table_denies

  @doc """
  Built-in schema-level deny patterns to apply when no adapter can be resolved.

  Callers with an `%Adapter{}` struct should prefer `builtin_schema_denies/1`.
  """
  @spec builtin_schema_denies() :: [String.t() | Regex.t()]
  def builtin_schema_denies, do: @fallback_schema_denies

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
  # Dispatch helpers — Pipeline (optional callbacks with defaults)
  # ---------------------------------------------------------------------------

  @doc "Validate statement safety via the adapter. Returns `:ok` if not implemented."
  @spec sanitize_query(t(), Statement.t(), keyword()) :: :ok | {:error, String.t()}
  def sanitize_query(%__MODULE__{module: mod, state: state}, %Statement{} = statement, opts) do
    if function_exported?(mod, :sanitize_query, 3),
      do: mod.sanitize_query(state, statement, opts),
      else: :ok
  end

  @doc """
  Rewrite the statement after variable substitution, before filters and sorts
  are applied. Returns the statement unchanged if the adapter doesn't
  implement `transform_bound_query/3`.
  """
  @spec transform_bound_query(t(), Statement.t(), keyword()) :: Statement.t()
  def transform_bound_query(
        %__MODULE__{module: mod, state: state},
        %Statement{} = statement,
        opts
      ) do
    if function_exported?(mod, :transform_bound_query, 3),
      do: mod.transform_bound_query(state, statement, opts),
      else: statement
  end

  @doc """
  Extract accessed resources for preflight checks. Returns
  `{:unrestricted, reason}` if the adapter doesn't implement the callback —
  callers must consult the host-app `:allow_unrestricted_resources` opt-in
  before allowing the statement through.
  """
  @spec extract_accessed_resources(t(), Statement.t()) ::
          {:ok, MapSet.t({String.t() | nil, String.t()})}
          | {:error, term()}
          | {:unrestricted, String.t()}
  def extract_accessed_resources(%__MODULE__{module: mod, state: state}, %Statement{} = statement) do
    if function_exported?(mod, :extract_accessed_resources, 2),
      do: mod.extract_accessed_resources(state, statement),
      else:
        {:unrestricted, "adapter #{inspect(mod)} does not implement extract_accessed_resources/2"}
  end

  @doc """
  Apply pagination to the statement. The paginated statement carries any
  count spec in `statement.meta[:count_spec]`. Returns the statement
  unchanged if the adapter doesn't implement `apply_pagination/3`.
  """
  @spec apply_pagination(t(), Statement.t(), keyword()) :: Statement.t()
  def apply_pagination(%__MODULE__{module: mod, state: state}, %Statement{} = statement, opts) do
    if function_exported?(mod, :apply_pagination, 3),
      do: mod.apply_pagination(state, statement, opts),
      else: statement
  end

  @doc """
  Whether the statement needs the visibility preflight check. Returns `true`
  if the adapter doesn't implement `needs_preflight?/2` — the safer default.
  """
  @spec needs_preflight?(t(), Statement.t()) :: boolean()
  def needs_preflight?(%__MODULE__{module: mod, state: state}, %Statement{} = statement) do
    if function_exported?(mod, :needs_preflight?, 2),
      do: mod.needs_preflight?(state, statement),
      else: true
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

  @doc "Apply filters to a statement via the adapter. Empty filters short-circuit."
  @spec apply_filters(t(), Statement.t(), list()) :: Statement.t()
  def apply_filters(_adapter, %Statement{} = statement, []), do: statement

  def apply_filters(%__MODULE__{module: mod, state: state}, %Statement{} = statement, filters) do
    mod.apply_filters(state, statement, filters)
  end

  @doc "Apply sorts to a statement via the adapter. Empty sorts short-circuit."
  @spec apply_sorts(t(), Statement.t(), list()) :: Statement.t()
  def apply_sorts(_adapter, %Statement{} = statement, []), do: statement

  def apply_sorts(%__MODULE__{module: mod, state: state}, %Statement{} = statement, sorts) do
    mod.apply_sorts(state, statement, sorts)
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

  @doc "Return the query language identifier via the adapter."
  @spec query_language(t()) :: String.t()
  def query_language(%__MODULE__{module: mod, state: state}) do
    if function_exported?(mod, :query_language, 1),
      do: mod.query_language(state),
      else: "sql"
  end

  @doc "Return editor configuration via the adapter."
  @spec editor_config(t()) :: map()
  def editor_config(%__MODULE__{module: mod, state: state}) do
    mod.editor_config(state)
  end

  @doc "Wrap a statement with a limit clause via the adapter."
  @spec limit_query(t(), String.t(), pos_integer()) :: String.t()
  def limit_query(%__MODULE__{module: mod, state: state}, statement, limit) do
    mod.limit_query(state, statement, limit)
  end

  @doc "Return the hierarchy label via the adapter."
  @spec hierarchy_label(t()) :: String.t()
  def hierarchy_label(%__MODULE__{module: mod, state: state}) do
    if function_exported?(mod, :hierarchy_label, 1),
      do: mod.hierarchy_label(state),
      else: "Tables"
  end

  @doc "Return an example query via the adapter."
  @spec example_query(t(), String.t(), String.t() | nil) :: String.t()
  def example_query(%__MODULE__{module: mod, state: state}, table, schema) do
    if function_exported?(mod, :example_query, 3),
      do: mod.example_query(state, table, schema),
      else: "SELECT value_column FROM #{table}"
  end

  @doc """
  Rewrite the statement before variable binding. Returns the statement
  unchanged if the adapter doesn't implement `transform_statement/2`.
  """
  @spec transform_statement(t(), Statement.t()) :: Statement.t()
  def transform_statement(%__MODULE__{module: mod, state: state}, %Statement{} = statement) do
    if function_exported?(mod, :transform_statement, 2),
      do: mod.transform_statement(state, statement),
      else: statement
  end

  @doc "Map a database type to a Lotus type via the adapter."
  @spec db_type_to_lotus_type(t(), String.t()) :: atom()
  def db_type_to_lotus_type(%__MODULE__{module: mod, state: state}, db_type) do
    mod.db_type_to_lotus_type(state, db_type)
  end
end
