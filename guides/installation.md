# Installation

This guide walks you through setting up Lotus in your Elixir application.

## Requirements

- Elixir 1.16 or later
- OTP 25 or later
- An Ecto-based application with PostgreSQL, MySQL, or SQLite
  - **SQLite**: Version 3.8.0+ recommended for database-level read-only protection

## Step 1: Add Dependency

Add `lotus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 0.8.0"}
  ]
end
```

Run `mix deps.get` to fetch the dependency.

## Step 2: Configuration

Add Lotus configuration to your `config/config.exs`:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,        # Where Lotus stores queries
  default_repo: "main",         # Default repo for queries (required with multiple repos)
  data_repos: %{                # Where queries execute
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

### Configuration Options

- `ecto_repo` (required): Repository where Lotus stores saved queries
- `data_repos` (required): Map of repositories where queries can be executed
- `default_repo`: Default repository name to use when none specified (required with multiple repos)
- `unique_names`: Whether to enforce unique query names (default: `true`)
- `table_visibility`: Rules controlling which tables can be accessed (optional)

## Step 3: Run Migrations

Lotus needs to create tables in your database to store queries. Generate and run the migration:

```bash
mix ecto.gen.migration create_lotus_tables
```

Add the Lotus migration to your generated migration file:

```elixir
defmodule MyApp.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration

  def up do
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end
```

Run the migration:

```bash
mix ecto.migrate
```

## Step 4: Add to Supervision Tree (Optional)

If you plan to use caching features, add Lotus to your application's supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    # Add Lotus for caching support
    Lotus,
    # Or with specific options:
    # {Lotus, cache: [adapter: Lotus.Cache.ETS, namespace: "prod"]},
    MyAppWeb.Endpoint
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Note**: This step is required only if you want to use caching. Without it, all Lotus query functions work normally, but caching will be disabled.

## Step 5: Verify Installation

Test that Lotus is working correctly:

```elixir
# In iex -S mix
iex> Lotus.run_sql("SELECT 1 as test")
{:ok, %Lotus.Result{rows: [[1]], columns: ["test"], num_rows: 1}}
```

## Database-Specific Setup

### PostgreSQL

Lotus works out of the box with PostgreSQL. Ensure your repository is configured with the `:postgrex` adapter:

```elixir
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev"
```

### SQLite

Lotus supports SQLite through the `ecto_sqlite3` adapter. Add the dependency to your `mix.exs`:

```elixir
{:ecto_sqlite3, "~> 0.11"}
```

Configure your SQLite repository:

```elixir
config :my_app, MyApp.SqliteRepo,
  adapter: Ecto.Adapters.SQLite3,
  database: Path.expand("../my_app.db", Path.dirname(__ENV__.file))
```

#### SQLite Security Features

Lotus provides database-level read-only protection for SQLite:

- **SQLite 3.8.0+** (2013): Supports `PRAGMA query_only` for database-level write prevention
- **Older versions**: Fall back to regex-based query validation (still secure)

The `PRAGMA query_only` feature provides an additional security layer by preventing INSERT, UPDATE, DELETE, CREATE, DROP, and other write operations at the database engine level, even if they somehow bypassed Lotus's regex validation.

### Mixed Database Environments

You can use different database types for storage and data:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,          # PostgreSQL for Lotus storage
  default_repo: "postgres",       # Default repository for queries
  data_repos: %{
    "postgres" => MyApp.Repo,     # PostgreSQL data
    "mysql" => MyApp.MySQLRepo,   # MySQL data
    "sqlite" => MyApp.SqliteRepo  # SQLite data
  }
```

### MySQL

Lotus supports MySQL through the `myxql` adapter. Add the dependency to your `mix.exs`:

```elixir
{:myxql, "~> 0.7"}
```

Configure your MySQL repository:

```elixir
config :my_app, MyApp.MySQLRepo,
  adapter: Ecto.Adapters.MyXQL,
  username: "root",
  password: "mysql",
  hostname: "localhost",
  database: "my_app_dev",
  port: 3306
```

## Session Management & Connection Pool Safety

Lotus implements robust session management to ensure database connections remain in their original state after query execution. This is critical in production environments where connection pooling is used.

### How It Works

Each database adapter uses a **snapshot/restore pattern**:

1. **Before execution**: Lotus snapshots the current session state
2. **During execution**: Lotus applies read-only mode and statement timeouts
3. **After execution**: Lotus automatically restores the original session state

This prevents "connection pool pollution" where one operation's settings affect subsequent operations using the same pooled connection.

### Database-Specific Behavior

#### PostgreSQL
- Uses `SET LOCAL` statements that automatically revert at transaction end
- **No session leakage** - settings are transaction-scoped only
- Minimal overhead with automatic cleanup

#### MySQL
- Snapshots and restores session-level settings:
  - `@@session.transaction_read_only` (access mode)
  - `@@session.transaction_isolation` (isolation level)
  - `@@session.max_execution_time` (statement timeout)
- **Cross-version compatible** - handles MySQL 5.7 vs 8.0+ differences
- Guaranteed restoration using `try/after` blocks

#### SQLite
- Snapshots and restores `PRAGMA query_only` setting
- **Graceful fallback** for SQLite versions < 3.8.0 that don't support the pragma
- Preserves original read-only state if database was already configured as read-only

### Why This Matters

Without proper session management, Lotus queries could leave database connections in unexpected states:

```elixir
# Without session management (problematic):
Lotus.run_sql("SELECT * FROM users")  # Sets read-only mode
MyApp.create_user(%{name: "John"})    # FAILS - connection still read-only!

# With Lotus session management (safe):
Lotus.run_sql("SELECT * FROM users")  # Sets + restores session state
MyApp.create_user(%{name: "John"})    # ✅ Works normally
```

This automatic session management ensures Lotus plays nicely with other parts of your application that share the same database connection pool.

## Troubleshooting

### Common Issues

**Configuration Error**: If you see `ArgumentError` with "Invalid :lotus config: required :ecto_repo option not found", ensure your repository is properly configured in your application config.

**Migration Issues**: If migrations fail, ensure your database is running and your repository configuration is correct.

**Permission Errors**: Lotus requires database access to create tables and execute queries. Ensure your database user has appropriate permissions.

## Next Steps

Now that Lotus is installed, check out the [Getting Started](getting-started.md) guide to create your first query.
