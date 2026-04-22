# Source Adapters

## Overview

Source adapters wrap data sources behind a uniform callback interface so that the Lotus execution pipeline does not depend on any particular database driver or connection strategy. Every data source -- whether it is an Ecto repo, a raw database connection, or an external API -- is represented as a `%Lotus.Source.Adapter{}` struct that the runner, preflight checks, and introspection modules all accept identically.

`Lotus.Source` provides convenience functions (`resolve!/2`, `source_type/1`, `supports_feature?/2`, `hierarchy_label/1`) that accept adapter structs, source name strings, or repo modules and resolve lazily as needed.

For SQL databases backed by Ecto, per-dialect adapter modules (`Lotus.Source.Adapters.Postgres`, `Lotus.Source.Adapters.MySQL`, `Lotus.Source.Adapters.SQLite3`) handle dialect-specific behaviour. External adapters for other databases or non-SQL data sources can be registered via the `source_adapters` config.

## How It Works

The adapter struct carries four fields:

| Field | Type | Description |
|---|---|---|
| `name` | `String.t()` | Human-readable identifier (e.g. `"main"`, `"warehouse"`) |
| `module` | `module()` | The module implementing `Lotus.Source.Adapter` callbacks |
| `state` | `term()` | Opaque connection state managed by the adapter (e.g. an Ecto.Repo module) |
| `source_type` | `atom()` | Database kind -- `:postgres`, `:mysql`, `:sqlite`, or `:other` |

When a query is executed, Lotus asks the configured **source resolver** to turn a repo name (or module) into an `%Adapter{}` struct. The resolver iterates through registered adapters (external first, then built-in per-dialect, then the generic Ecto fallback), calling `can_handle?/1` on each until one claims the repo. That adapter's `wrap/2` builds the struct, and from that point every pipeline stage dispatches through `Adapter` dispatch helpers.

```
User calls Lotus.run_statement("SELECT 1", [], repo: "main")
  |
  v
Source Resolver  -->  per-dialect adapter (Adapters.Postgres)  -->  %Adapter{name: "main", module: Adapters.Postgres, state: MyApp.Repo, source_type: :postgres}
  |
  v
Runner / Preflight / Schema  -->  Adapter.execute_query(adapter, sql, params, opts)
                                     +-->  Adapters.Postgres.execute_query(MyApp.Repo, sql, params, opts)
```

## Default Behaviour

If you are using Ecto repos and static configuration, no changes are needed. The default source resolver (`Lotus.Source.Resolvers.Static`) reads your existing `data_sources` config and wraps each repo in the appropriate per-dialect adapter automatically:

- PostgreSQL repos (`Ecto.Adapters.Postgres`) get `Lotus.Source.Adapters.Postgres`
- MySQL repos (`Ecto.Adapters.MyXQL`) get `Lotus.Source.Adapters.MySQL`
- SQLite repos (`Ecto.Adapters.SQLite3`) get `Lotus.Source.Adapters.SQLite3`
- Unknown Ecto repos fall back to `Lotus.Source.Adapters.Ecto` with the `Default` dialect

Standard Ecto configuration:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,
  default_source: "main",
  data_sources: %{
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

The public API (`Lotus.run_query/2`, `Lotus.run_statement/3`, etc.) is unchanged.

## Configuration

Three config keys control how adapters and visibility rules are resolved:

```elixir
config :lotus,
  # Determines how repo names are resolved to %Adapter{} structs.
  # Default: Lotus.Source.Resolvers.Static
  source_resolver: MyApp.SourceResolver,

  # List of external adapter modules consulted before built-in adapters.
  # Each must implement can_handle?/1 and wrap/2.
  # Default: []
  source_adapters: [MyApp.MSSQLAdapter],

  # Determines how visibility rules (schema, table, column) are loaded.
  # Default: Lotus.Visibility.Resolvers.Static
  visibility_resolver: MyApp.VisibilityResolver
```

All keys are optional. When omitted, the defaults read from static application config.

## Building a Custom Adapter

There are two paths depending on whether your data source uses Ecto.

### A. Ecto-backed adapter (new SQL dialect)

Use this path when Ecto already has a driver for the database (e.g. `Tds` for MSSQL) but Lotus does not ship a built-in dialect for it.

**Step 1: Write a Dialect module** implementing `Lotus.Source.Adapters.Ecto.Dialect`. The dialect encapsulates all SQL-specific behaviour for that database.

**Step 2: Write an adapter module** that pulls in the shared Ecto machinery via `use Lotus.Source.Adapters.Ecto`.

**Step 3: Register** the adapter via the `source_adapters` config key.

```elixir
defmodule MyApp.Dialects.MSSQL do
  @behaviour Lotus.Source.Adapters.Ecto.Dialect

  # -- Identity ---------------------------------------------------------------
  @impl true
  def source_type, do: :mssql

  @impl true
  def ecto_adapter, do: Ecto.Adapters.Tds

  @impl true
  def query_language, do: "sql:tsql"

  @impl true
  def limit_query(statement, limit), do: "SELECT TOP #{limit} * FROM (#{statement}) AS t"

  # -- Transaction & session --------------------------------------------------
  # execute_in_transaction/3, set_statement_timeout/2, set_search_path/2

  # -- Error handling ---------------------------------------------------------
  # format_error/1, handled_errors/0

  # -- SQL generation ---------------------------------------------------------
  # quote_identifier/1, param_placeholder/3, limit_offset_placeholders/2,
  # apply_filters/3, apply_sorts/2, explain_plan/4

  # -- Visibility & deny rules -----------------------------------------------
  # builtin_denies/1, builtin_schema_denies/1, default_schemas/1

  # -- Introspection ----------------------------------------------------------
  # list_schemas/1, list_tables/3, get_table_schema/3, resolve_table_schema/3
end

defmodule MyApp.Adapters.MSSQL do
  use Lotus.Source.Adapters.Ecto, dialect: MyApp.Dialects.MSSQL
end
```

#### Dialect callbacks

Callbacks are organized by category. All required callbacks must be implemented. Optional callbacks have sensible defaults provided by the behaviour.

**Required:**

| Callback | Category |
|---|---|
| `source_type/0` | Identity |
| `ecto_adapter/0` | Identity |
| `query_language/0` | Identity |
| `limit_query/2` | Identity |
| `execute_in_transaction/3` | Transaction and session |
| `set_statement_timeout/2` | Transaction and session |
| `set_search_path/2` | Transaction and session |
| `format_error/1` | Error handling |
| `handled_errors/0` | Error handling |
| `quote_identifier/1` | SQL generation |
| `param_placeholder/3` | SQL generation |
| `limit_offset_placeholders/2` | SQL generation |
| `apply_filters/3` | SQL generation |
| `apply_sorts/2` | SQL generation |
| `explain_plan/4` | SQL generation |
| `builtin_denies/1` | Visibility and deny rules |
| `builtin_schema_denies/1` | Visibility and deny rules |
| `default_schemas/1` | Visibility and deny rules |
| `list_schemas/1` | Introspection |
| `list_tables/3` | Introspection |
| `get_table_schema/3` | Introspection |
| `resolve_table_schema/3` | Introspection |

**Optional** (defaults provided):

| Callback | Category | Default behaviour |
|---|---|---|
| `supports_feature?/1` | Identity | Returns `false` |
| `hierarchy_label/0` | Identity | Returns `"Schema"` |
| `example_query/2` | Identity | Returns a generic `SELECT *` query |
| `editor_config/0` | Editor | Returns empty config (`%{language: "sql", keywords: [], ...}`) |
| `extract_accessed_resources/4` | SQL analysis | Delegates to `EXPLAIN`-based extraction |
| `transform_sql/1` | SQL transformation | Returns the SQL unchanged |
| `db_type_to_lotus_type/1` | Type mapping | Maps common SQL types to Lotus types |

### B. Non-Ecto adapter (REST API, document store, etc.)

Use this path for data sources that do not use Ecto at all (e.g. Elasticsearch, MongoDB, a REST API).

Implement the `Lotus.Source.Adapter` behaviour directly. A minimal adapter looks like the stub below — an in-memory "echo" source that returns the submitted statement as a row. It shows the shape of every required callback; swap the bodies with real HTTP calls (or whatever transport your source speaks) to ship a production adapter.

```elixir
defmodule MyApp.Adapters.Echo do
  @behaviour Lotus.Source.Adapter

  # -- Resolution -------------------------------------------------------------
  # Decide which data_sources entries this adapter claims. Lotus dispatches to
  # the first adapter whose can_handle?/1 returns true.
  @impl true
  def can_handle?(%{adapter: :echo}), do: true
  def can_handle?(_), do: false

  @impl true
  def wrap(name, %{adapter: :echo} = config) do
    %Lotus.Source.Adapter{
      name: name,
      module: __MODULE__,
      state: config,
      source_type: :echo
    }
  end

  # -- Query execution --------------------------------------------------------
  # The :statement argument is whatever query language the source understands
  # (SQL, JSON DSL, Cypher, etc.). Return a result map with :columns, :rows,
  # :num_rows — Lotus wraps it into a %Lotus.Result{} struct.
  @impl true
  def execute_query(_state, statement, params, _opts) do
    {:ok,
     %{
       columns: ["statement", "param_count"],
       rows: [[statement, length(params)]],
       num_rows: 1
     }}
  end

  # Non-transactional sources can run the fun directly.
  @impl true
  def transaction(state, fun, _opts), do: {:ok, fun.(state)}

  # -- Introspection ----------------------------------------------------------
  # Power the schema browser. Return empty lists if your source has no
  # schemas/tables concept.
  @impl true
  def list_schemas(_state), do: {:ok, ["default"]}

  @impl true
  def list_tables(_state, _schemas, _opts), do: {:ok, [{"default", "messages"}]}

  @impl true
  def get_table_schema(_state, _schema, _table), do: {:ok, []}

  @impl true
  def resolve_table_schema(_state, _table, _schemas), do: {:ok, nil}

  # -- SQL generation (no-ops are fine for non-SQL sources) -------------------
  @impl true
  def quote_identifier(_state, id), do: id

  @impl true
  def param_placeholder(_state, _idx, _var, _type), do: ""

  @impl true
  def limit_offset_placeholders(_state, _l, _o), do: {"", ""}

  @impl true
  def apply_filters(_state, statement, params, _filters), do: {statement, params}

  @impl true
  def apply_sorts(_state, statement, _sorts), do: statement

  @impl true
  def limit_query(_state, statement, _limit), do: statement

  @impl true
  def explain_plan(_state, _statement, _params, _opts),
    do: {:error, "EXPLAIN not supported for echo sources"}

  # -- Safety and visibility --------------------------------------------------
  @impl true
  def builtin_denies(_state), do: []

  @impl true
  def builtin_schema_denies(_state), do: []

  @impl true
  def default_schemas(_state), do: ["default"]

  # -- Error handling ---------------------------------------------------------
  @impl true
  def format_error(_state, error), do: inspect(error)

  @impl true
  def handled_errors(_state), do: []

  # -- Identity ---------------------------------------------------------------
  @impl true
  def source_type(_state), do: :echo

  @impl true
  def supports_feature?(_state, _feature), do: false

  @impl true
  def db_type_to_lotus_type(_state, _db_type), do: :text

  @impl true
  def editor_config(_state),
    do: %{language: "echo", keywords: [], types: [], functions: [], context_boundaries: []}

  # -- Lifecycle --------------------------------------------------------------
  @impl true
  def health_check(_state), do: :ok

  @impl true
  def disconnect(_state), do: :ok
end
```

Register it and use it like any other source:

```elixir
config :lotus,
  source_adapters: [MyApp.Adapters.Echo],
  data_sources: %{"echo" => %{adapter: :echo}}

{:ok, result} = Lotus.run_statement("hello", [1, 2, 3], repo: "echo")
# result.rows #=> [["hello", 3]]
```

Optional callbacks non-SQL adapters usually don't implement:

- `sanitize_query/3` — Lotus defaults to `:ok`. Return `{:error, reason}` to reject malformed statements (JSON schema checks, DSL validation).
- `transform_statement/2` / `transform_bound_query/4` — default to passthrough. Implement only if your statement text needs pre- or post-binding rewrites.
- `extract_accessed_resources/4` — default is `:skip`, which makes `Lotus.Preflight` authorize everything that passes your own `sanitize_query`. Implement to wire up visibility rules against the tables/indices/collections a query will touch.
- `apply_pagination/4` — default is `{query, params, nil}`. Implement to support `window: [limit:, offset:, count:]` pagination in your source's native syntax.

For a real-world reference, see [`lotus_elasticsearch`](https://github.com/elixir-lotus/lotus_elasticsearch), which implements this contract against the Elasticsearch Query DSL.

## Editor Configuration

The optional `editor_config/0` callback allows dialects to provide keywords, types, function completions, and context boundaries for the web UI's SQL editor. This enables dialect-specific syntax highlighting and autocomplete without hardcoding database knowledge in the frontend.

```elixir
@impl true
def editor_config do
  %{
    language: "sql",
    keywords: ~w(PREWHERE FINAL SAMPLE SETTINGS FORMAT ENGINE),
    types: ~w(UInt8 UInt64 Float64 Array LowCardinality Nullable),
    functions: [
      %{name: "uniq", detail: "Approx distinct count", args: "(column)"},
      %{name: "arrayJoin", detail: "Unpack array to rows", args: "(array)"},
      %{name: "toDate", detail: "Convert to Date", args: "(value)"}
    ],
    context_boundaries: ~w(prewhere final sample settings format)
  }
end
```

**Fields:**

- `language` — parser to use on the JS side (`"sql"` for all SQL dialects)
- `keywords` — dialect-specific keywords for syntax highlighting (merged with standard SQL keywords by the frontend)
- `types` — dialect-specific type names for syntax highlighting
- `functions` — function completions with name, description, and argument template
- `context_boundaries` — keywords that mark clause boundaries for context-aware completions (e.g., ClickHouse's `PREWHERE` is treated like `WHERE` for column suggestions)

When not implemented, the frontend uses standard SQL defaults. For large function lists, consider extracting the data into a dedicated `EditorConfig` submodule (see `lotus_clickhouse` for an example with 300+ functions).

## Registration

Custom adapters are registered via the `source_adapters` config key:

```elixir
config :lotus,
  source_adapters: [MyApp.Adapters.MSSQL, MyApp.Adapters.Elasticsearch]
```

**Resolution order:** When the resolver needs to wrap a repo, it checks adapters in this order:

1. External adapters (from `source_adapters` config), in list order
2. Built-in per-dialect adapters (`Adapters.Postgres`, `Adapters.MySQL`, `Adapters.SQLite3`)
3. Generic Ecto fallback (`Adapters.Ecto` with `Default` dialect)

The first adapter whose `can_handle?/1` returns `true` wins. This means external adapters can override built-in handling for a given Ecto adapter if needed.

## Custom Resolvers

Both extension points that feed the adapter pipeline -- how repo names are turned into `%Adapter{}` structs, and how visibility rules are loaded -- are pluggable behaviours:

- `Lotus.Source.Resolver` -- resolves repo opts into `%Adapter{}` structs
- `Lotus.Visibility.Resolver` -- loads schema, table, and column visibility rules

Both ship with static defaults (`Lotus.Source.Resolvers.Static`, `Lotus.Visibility.Resolvers.Static`) that read from application config. Custom implementations let you load sources and rules from a database, registry, or external service at runtime -- without forking Lotus.

See the dedicated [Custom Resolvers guide](custom-resolvers.md) for contracts, full `Agent`- and ETS-backed examples, and testing guidance.
