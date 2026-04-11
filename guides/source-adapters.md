# Source Adapters

## Overview

Source adapters wrap data sources behind a uniform callback interface so that the Lotus execution pipeline does not depend on any particular database driver or connection strategy. Every data source — whether it is an Ecto repo, a raw database connection, or an external API — is represented as a `%Lotus.Source.Adapter{}` struct that the runner, preflight checks, and introspection modules all accept identically.

## How It Works

The adapter struct carries four fields:

| Field | Type | Description |
|---|---|---|
| `name` | `String.t()` | Human-readable identifier (e.g. `"main"`, `"warehouse"`) |
| `module` | `module()` | The module implementing `Lotus.Source.Adapter` callbacks |
| `state` | `term()` | Opaque connection state managed by the adapter (e.g. an Ecto.Repo module) |
| `source_type` | `atom()` | Database kind — `:postgres`, `:mysql`, `:sqlite`, or `:other` |

When a query is executed, Lotus asks the configured **source resolver** to turn a repo name (or module) into an `%Adapter{}` struct. The resolver returns the struct, and from that point every pipeline stage — SQL generation, preflight authorization, execution, introspection — dispatches through `Adapter` dispatch helpers which delegate to the underlying `module`, passing `state` as the first argument.

```
User calls Lotus.run_sql("SELECT 1", [], repo: "main")
  │
  ▼
Source Resolver  ──▶  %Adapter{name: "main", module: Ecto, state: MyApp.Repo, source_type: :postgres}
  │
  ▼
Runner / Preflight / Schema  ──▶  Adapter.execute_query(adapter, sql, params, opts)
                                     └─▶  Ecto.execute_query(MyApp.Repo, sql, params, opts)
```

## Default Behaviour

If you are using Ecto repos and static configuration, no changes are needed. The default source resolver (`Lotus.Source.Resolvers.Static`) reads your existing `data_sources` config and wraps each repo in `Lotus.Source.Adapters.Ecto` automatically. Your existing configuration continues to work as before:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,
  default_source: "main",
  data_sources: %{
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

The public API (`Lotus.run_query/2`, `Lotus.run_sql/3`, etc.) is unchanged.

## Configuration

Two config keys control how adapters and visibility rules are resolved:

```elixir
config :lotus,
  # Determines how repo names are resolved to %Adapter{} structs.
  # Default: Lotus.Source.Resolvers.Static
  source_resolver: MyApp.SourceResolver,

  # Determines how visibility rules (schema, table, column) are loaded.
  # Default: Lotus.Visibility.Resolvers.Static
  visibility_resolver: MyApp.VisibilityResolver
```

Both keys are optional. When omitted, the defaults read from static application config — the same behaviour Lotus has always had.

## Custom Resolvers

Both extension points that feed the adapter pipeline — how repo names are turned into `%Adapter{}` structs, and how visibility rules are loaded — are pluggable behaviours:

- `Lotus.Source.Resolver` — resolves repo opts into `%Adapter{}` structs
- `Lotus.Visibility.Resolver` — loads schema, table, and column visibility rules

Both ship with static defaults (`Lotus.Source.Resolvers.Static`, `Lotus.Visibility.Resolvers.Static`) that read from application config. Custom implementations let you load sources and rules from a database, registry, or external service at runtime — without forking Lotus.

See the dedicated [Custom Resolvers guide](custom-resolvers.md) for contracts, full `Agent`- and ETS-backed examples, and testing guidance.

## Custom Adapters

To support a non-Ecto data source, implement the `Lotus.Source.Adapter` behaviour directly. Callbacks are grouped into categories:

**Query execution** — `execute_query/4`, `transaction/3`

**Introspection** — `list_schemas/1`, `list_tables/3`, `get_table_schema/3`, `resolve_table_schema/3`

**SQL generation** — `quote_identifier/2`, `param_placeholder/4`, `limit_offset_placeholders/3`, `apply_filters/4`, `apply_sorts/3`, `explain_plan/4`

**Safety and visibility** — `builtin_denies/1`, `builtin_schema_denies/1`, `default_schemas/1`

**Lifecycle** — `health_check/1`, `disconnect/1`

**Error handling** — `format_error/2`, `handled_errors/1`

**Source identity** — `source_type/1`, `supports_feature?/2`

All callbacks receive `state` as their first argument — the opaque value stored in the adapter struct. For example, an adapter wrapping a raw `Postgrex` connection pool might store the pool pid as `state`:

```elixir
defmodule MyApp.RawPostgresAdapter do
  @behaviour Lotus.Source.Adapter

  def wrap(name, pool_pid) do
    %Lotus.Source.Adapter{
      name: name,
      module: __MODULE__,
      state: pool_pid,
      source_type: :postgres
    }
  end

  @impl true
  def execute_query(pool_pid, sql, params, opts) do
    case Postgrex.query(pool_pid, sql, params, opts) do
      {:ok, %{columns: cols, rows: rows, num_rows: n}} ->
        {:ok, %{columns: cols, rows: rows, num_rows: n}}
      {:error, err} ->
        {:error, Exception.message(err)}
    end
  end

  # ... implement remaining callbacks
end
```

See `Lotus.Source.Adapters.Ecto` for a complete reference implementation.
