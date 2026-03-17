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
| `source_type` | `atom()` | Database kind — `:postgres`, `:mysql`, `:sqlite`, `:tds`, or `:other` |

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

If you are using Ecto repos and static configuration, no changes are needed. The default source resolver (`Lotus.Source.Resolvers.Static`) reads your existing `data_repos` config and wraps each repo in `Lotus.Source.Adapters.Ecto` automatically. Your existing configuration continues to work as before:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,
  default_repo: "main",
  data_repos: %{
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

## Custom Source Resolvers

Implement the `Lotus.Source.Resolver` behaviour to load data sources dynamically — for example from a database registry or an external service.

```elixir
defmodule MyApp.SourceResolver do
  @behaviour Lotus.Source.Resolver

  @impl true
  def resolve(repo_opt, _fallback) do
    case MyApp.DataSources.find(repo_opt) do
      nil -> {:error, :not_found}
      source -> {:ok, build_adapter(source)}
    end
  end

  @impl true
  def list_sources do
    MyApp.DataSources.all()
    |> Enum.map(&build_adapter/1)
  end

  @impl true
  def get_source!(name) do
    source = MyApp.DataSources.find!(name)
    build_adapter(source)
  end

  @impl true
  def list_source_names do
    MyApp.DataSources.all()
    |> Enum.map(& &1.name)
  end

  @impl true
  def default_source do
    source = MyApp.DataSources.default!()
    {source.name, build_adapter(source)}
  end

  defp build_adapter(source) do
    Lotus.Source.Adapters.Ecto.wrap(source.name, source.repo_module)
  end
end
```

Then configure it:

```elixir
config :lotus,
  source_resolver: MyApp.SourceResolver
```

The five required callbacks are:

| Callback | Returns |
|---|---|
| `resolve/2` | `{:ok, %Adapter{}}` or `{:error, term()}` |
| `list_sources/0` | `[%Adapter{}]` |
| `get_source!/1` | `%Adapter{}` (raises on missing) |
| `list_source_names/0` | `[String.t()]` |
| `default_source/0` | `{name, %Adapter{}}` |

## Custom Visibility Resolvers

Implement `Lotus.Visibility.Resolver` to load visibility rules from a database or per-tenant configuration instead of static config.

```elixir
defmodule MyApp.VisibilityResolver do
  @behaviour Lotus.Visibility.Resolver

  @impl true
  def schema_rules_for(source_name) do
    case MyApp.VisibilityStore.get_schema_rules(source_name) do
      nil -> [allow: :all, deny: []]
      rules -> rules
    end
  end

  @impl true
  def table_rules_for(source_name) do
    case MyApp.VisibilityStore.get_table_rules(source_name) do
      nil -> [allow: [], deny: []]
      rules -> rules
    end
  end

  @impl true
  def column_rules_for(source_name) do
    MyApp.VisibilityStore.get_column_rules(source_name) || []
  end
end
```

Then configure it:

```elixir
config :lotus,
  visibility_resolver: MyApp.VisibilityResolver
```

The three required callbacks are:

| Callback | Returns |
|---|---|
| `schema_rules_for/1` | `keyword()` — e.g. `[allow: [...], deny: [...]]` |
| `table_rules_for/1` | `keyword()` — e.g. `[allow: [...], deny: [...]]` |
| `column_rules_for/1` | `list()` — column rule tuples |

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
