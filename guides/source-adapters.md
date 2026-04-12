# Source Adapters

## Overview

Source adapters wrap data sources behind a uniform callback interface so that the Lotus execution pipeline does not depend on any particular database driver or connection strategy. Every data source -- whether it is an Ecto repo, a raw database connection, or an external API -- is represented as a `%Lotus.Source.Adapter{}` struct that the runner, preflight checks, and introspection modules all accept identically.

`Lotus.Source` is a **facade module** (similar to `Lotus.Cache`). It provides convenience functions like `resolve!/2`, `source_type/1`, `supports_feature?/2`, and `hierarchy_label/1` that accept adapter structs, source name strings, or raw repo modules and resolve lazily as needed.

For SQL databases backed by Ecto, per-dialect adapter modules (`Lotus.Source.Adapters.Postgres`, `Lotus.Source.Adapters.MySQL`, `Lotus.Source.Adapters.SQLite3`) handle dialect-specific behaviour automatically. A pluggable registry (`source_adapters` config) lets you add custom adapters for databases or non-SQL data sources without forking Lotus.

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

Your existing configuration continues to work as before:

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
  def query_language, do: "T-SQL"

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
| `extract_accessed_resources/4` | SQL analysis | Delegates to `EXPLAIN`-based extraction |
| `transform_sql/1` | SQL transformation | Returns the SQL unchanged |
| `db_type_to_lotus_type/1` | Type mapping | Maps common SQL types to Lotus types |

### B. Non-Ecto adapter (REST API, document store, etc.)

Use this path for data sources that do not use Ecto at all (e.g. Elasticsearch, MongoDB, a REST API).

Implement the `Lotus.Source.Adapter` behaviour directly. The adapter must handle resolution (`can_handle?/1`, `wrap/2`), query execution, introspection, SQL generation helpers, and error handling.

```elixir
defmodule MyApp.Adapters.Elasticsearch do
  @behaviour Lotus.Source.Adapter

  # -- Resolution -------------------------------------------------------------
  @impl true
  def can_handle?(%{adapter: :elasticsearch}), do: true
  def can_handle?(_), do: false

  @impl true
  def wrap(name, config) do
    %Lotus.Source.Adapter{
      name: name,
      module: __MODULE__,
      state: config,
      source_type: :elasticsearch
    }
  end

  # -- Query execution --------------------------------------------------------
  # execute_query/4, transaction/3

  # -- Introspection ----------------------------------------------------------
  # list_schemas/1, list_tables/3, get_table_schema/3, resolve_table_schema/3

  # -- SQL generation (may return no-ops for non-SQL sources) -----------------
  # quote_identifier/2, param_placeholder/4, apply_filters/4, apply_sorts/3,
  # explain_plan/4, limit_offset_placeholders/3

  # -- Safety and visibility --------------------------------------------------
  # builtin_denies/1, builtin_schema_denies/1, default_schemas/1

  # -- Error handling ---------------------------------------------------------
  # format_error/2, handled_errors/1

  # -- Identity ---------------------------------------------------------------
  # source_type/1, supports_feature?/2, query_language/1, limit_query/2,
  # hierarchy_label/1, example_query/2

  # -- SQL analysis (non-SQL adapters typically return :skip) ------------------
  # extract_accessed_resources/4 -> :skip
  # sanitize_query/3, transform_query/4

  # -- Lifecycle --------------------------------------------------------------
  # health_check/1, disconnect/1
end
```

Note that non-SQL adapters may return `:skip` from `extract_accessed_resources` and implement `sanitize_query` / `transform_query` differently than SQL adapters.

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
