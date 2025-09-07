# Lotus

[Try the demo here](https://lotus.typhoon.works/)

![Lotus](https://raw.githubusercontent.com/typhoonworks/lotus/main/media/banner.png)

<p>
  <a href="https://hex.pm/packages/lotus">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/lotus.svg">
  </a>
  <a href="https://hexdocs.pm/lotus">
    <img src="https://img.shields.io/badge/docs-hexdocs-blue" alt="HexDocs">
  </a>
  <a href="https://github.com/typhoonworks/lotus/actions">
    <img alt="CI Status" src="https://github.com/typhoonworks/lotus/workflows/ci/badge.svg">
  </a>
</p>

Lotus is a lightweight SQL query runner and storage library for Elixir applications with Ecto. It provides a safe, read-only environment for executing analytical queries while offering organized storage and management of saved queries.

>🚧 While this library already ships a lot of features and the public API is mostly set, it’s still evolving. We’ll make a best effort to announce breaking changes, but we can’t guarantee backwards compatibility yet — especially as we generalize the `Source` abstraction to support more than SQL-backed data sources.

## Production Use and UUID Caveats

Lotus is generally safe to run in production: it executes queries in read‑only transactions and restores session state (timeouts, isolation, etc.) to avoid pool pollution. We are running it in [Accomplish](https://accomplish.dev) successfully in production today, notwithanding being affected by the limitation described below.

If your application uses UUIDs or mixed ID formats across databases, there are current limitations to be aware of:

- Runtime Lotus query variable binding around UUID columns can be constrained across different storage types:
  - PostgreSQL `uuid`
  - MySQL `BINARY(16)` vs `CHAR(36|32)`
  - SQLite `TEXT` vs `BLOB`
- Queries still work, and you can get a lot of value, but in some cases you may need explicit casts or to shape values to match the column’s storage format when using `{{var}}` in predicates against UUID columns. This limitation particularly affects the Lotus Web library today — there isn’t a built‑in workaround in the UI for column‑specific typing/casting yet.

We plan to improve this with column‑aware binding (using schema metadata per adapter to deterministically cast/shape values for the true column type). Until then, keep the above in mind when authoring queries that filter on UUID columns.

## Lotus Web UI

While Lotus can be used standalone, it pairs naturally with [Lotus Web](https://github.com/typhoonworks/lotus_web) (v0.4+ for Lotus 0.9), which provides a beautiful web interface you can mount directly in your Phoenix application:

- 🖥️ **Web-based SQL editor** with syntax highlighting and autocomplete
- 🗂️ **Query management** - save, organize, and reuse SQL queries
- 🔍 **Schema explorer** - browse tables and columns interactively
- 📊 **Results visualization** - clean, tabular display with export capabilities
- ⚡ **LiveView-powered** - real-time query execution without page refreshes
- 🔒 **Secure by default** - leverages Lotus's read-only architecture

Learn more about setting up Lotus Web in the [installation guide](guides/installation.md#lotus-web-setup).

## Current Features
- 🔐 **Enhanced security** with read-only execution, table visibility controls, and automatic session state management
- 📦 **Query storage and management** - save, organize, and reuse SQL queries
- 🏗️ **Multi-database support** - PostgreSQL, MySQL, and SQLite with flexible repository architecture
- ⚡ **Configurable execution** with timeout controls and connection management
- 🎯 **Type-safe results** with structured query result handling
- 🛡️ **Defense-in-depth** with preflight authorization and built-in system table protection
- 💾 **Result caching** with TTL-based expiration, cache profiles, and tag-based invalidation

### Production-Safe Connection Pooling
Lotus automatically preserves your database session state to prevent connection pool pollution. When a query completes, all session settings (read-only mode, timeouts, isolation levels) are restored to their original values, ensuring Lotus doesn't interfere with other parts of your application. [Learn more about session management →](guides/installation.md#session-management--connection-pool-safety)

## What's planned?
- [ ] Query versioning and change tracking
- [ ] Export functionality for query results (CSV, JSON)
- [ ] Column-level visibility and access control
- [ ] Cache statistics and monitoring (`Lotus.Cache.stats()`)
- [ ] Additional cache backends (Redis, Memcached)
- [ ] Telemetry integration for cache metrics and query performance
- [x] Query result caching with ETS backend
- [x] MySQL support
- [x] Multi-database support (PostgreSQL, MySQL, SQLite)
- [x] Table visibility and access controls
- [x] Query templates with parameter substitution using `{{var}}` placeholders

## Installation
Add `lotus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 0.9.3"}
  ]
end
```

Lotus requires Elixir 1.16 or later, and OTP 25 or later. It may work with earlier versions, but it wasn't tested against them.

Follow the [installation instructions](guides/installation.md) to set up Lotus in your application.

## Migration Guide

### Upgrading from versions < 0.9.0

If you're upgrading from a version prior to 0.9.0 and have stored queries with `static_options`, you'll need to migrate your data. The `static_options` field format has changed from simple string arrays to structured maps.

**Old format:**
```elixir
"static_options" => ["Bob", "Alice", "Charlie"]
```

**New format:**
```elixir
"static_options" => [
  %{"value" => "Bob", "label" => "Bob"},
  %{"value" => "Alice", "label" => "Alice"},
  %{"value" => "Charlie", "label" => "Charlie"}
]
```

**Migration script:**
```elixir
# Run this in your application console (iex -S mix)
import Ecto.Query

# Use the same repo that Lotus is configured to store queries in
repo = Lotus.repo()  # Returns the configured ecto_repo

# Get all queries (raw data to bypass Ecto schema loading)
{:ok, result} = repo.query("SELECT id, name, variables FROM lotus_queries")

# Process each row
for [id, name, variables] <- result.rows do
  needs_migration =
    Enum.any?(variables, fn var ->
      case var["static_options"] do
        [first | _] when is_binary(first) -> true
        _ -> false
      end
    end)

  if needs_migration do
    IO.puts("Migrating query: #{name}")

    updated_variables =
      Enum.map(variables, fn var ->
        case var["static_options"] do
          options when is_list(options) ->
            migrated_options =
              Enum.map(options, fn
                opt when is_binary(opt) -> %{"value" => opt, "label" => opt}
                opt -> opt  # Already migrated or other format
              end)
            Map.put(var, "static_options", migrated_options)

          _ -> var
        end
      end)

    {:ok, _} = repo.query("""
      UPDATE lotus_queries
      SET variables = $1, updated_at = NOW()
      WHERE id = $2
    """, [updated_variables, id])

    IO.puts("✓ Updated query #{name}")
  end
end
```

## Getting Started
Take a look at the [overview guide](guides/overview.md) for a quick introduction to Lotus.

## Configuration
View all the configuration options in the [configuration guide](guides/configuration.md).

## Basic Usage

### Configuration
Add to your config:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,    # Repo where Lotus stores saved queries
  default_repo: "main",     # Default repo for queries (required with multiple repos)
  data_repos: %{            # Repos where queries run against actual data
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo,
    "mysql" => MyApp.MySQLRepo
  }

# Optional: Configure caching (ETS adapter included)
config :lotus,
  cache: [
    adapter: Lotus.Cache.ETS,
    profiles: %{
      results: [ttl: 60_000],      # Cache query results for 1 minute
      schema: [ttl: 3_600_000],    # Cache table schemas for 1 hour
      options: [ttl: 300_000]      # Cache query options for 5 minutes
    }
  ]
```

### Creating and Running Queries

```elixir
# Create and save a query
{:ok, query} = Lotus.create_query(%{
  name: "Active Users",
  statement: "SELECT * FROM users WHERE active = true"
})

# Execute a saved query
{:ok, results} = Lotus.run_query(query)

# Execute SQL directly (read-only)
{:ok, results} = Lotus.run_sql("SELECT * FROM products WHERE price > $1", [100])

# Execute against a specific data repository
{:ok, results} = Lotus.run_sql("SELECT COUNT(*) FROM events", [], repo: "analytics")
```

## Development Setup

### Prerequisites
- PostgreSQL (tested with version 14+)
- MySQL (tested with version 8.0+)
- SQLite 3
- Elixir 1.16+
- OTP 25+

### Setting up the development environment

1. Clone the repository and install dependencies:
```bash
git clone https://github.com/typhoonworks/lotus.git
cd lotus
mix deps.get
```

2. Set up the development databases:
```bash
# Start MySQL with Docker Compose (optional)
docker compose up -d mysql

# Create and migrate databases
mix ecto.create
mix ecto.migrate
```

This creates:
- PostgreSQL database (`lotus_dev`) with both Lotus tables and test data tables
- MySQL database (`lotus_dev`) via Docker Compose on port 3307
- SQLite database (`lotus_dev.db`) with e-commerce sample data

### Running tests

```bash
# Run all tests
mix test

# Run specific test files
mix test test/lotus_test.exs

# Run with coverage
mix test --cover
```

The test suite uses separate databases:
- PostgreSQL: `lotus_test` (with partitioning for parallel tests)
- MySQL: `lotus_test` (via Docker Compose)
- SQLite: `lotus_sqlite_test.db`

## Contributing
See the [contribution guide](guides/contributing.md) for details on how to contribute to Lotus.

## License
This project is licensed under the MIT License - see the LICENSE file for details.
