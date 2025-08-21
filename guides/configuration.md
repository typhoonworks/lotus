# Configuration

This guide covers all configuration options available in Lotus and how to customize the library for your specific needs.

## Basic Configuration

Lotus configuration is typically placed in your `config/config.exs` file:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,        # Repository for Lotus query storage
  data_repos: %{                 # Repositories for executing queries
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

## Configuration Options

### Required Options

#### `ecto_repo` (required)

Specifies the Ecto repository where Lotus stores saved queries. This is where the `lotus_queries` table lives.

```elixir
config :lotus,
  ecto_repo: MyApp.Repo
```

**Type**: `module()`

#### `data_repos` (required)

A map of repositories where queries can be executed against actual data. This powerful feature allows Lotus to work with multiple databases simultaneously, supporting both PostgreSQL and SQLite.

Keys are friendly names that you use when executing queries, values are Ecto repository modules.

```elixir
config :lotus,
  data_repos: %{
    "main" => MyApp.Repo,           # Can be the same as ecto_repo
    "analytics" => MyApp.AnalyticsRepo,
    "reporting" => MyApp.ReportingRepo,
    "sqlite_data" => MyApp.SqliteRepo   # Mix database types
  }
```

**Type**: `%{String.t() => module()}`

**Usage Examples:**

```elixir
# Execute against a specific repository by name
Lotus.run_sql("SELECT COUNT(*) FROM users", [], repo: "analytics")

# Execute against a repository module directly
Lotus.run_sql("SELECT COUNT(*) FROM users", [], repo: MyApp.AnalyticsRepo)

# When no repo is specified, uses the first configured data repo (alphabetically)
Lotus.run_sql("SELECT COUNT(*) FROM users")
```

**Repository Management:**

```elixir
# List all configured data repository names
repo_names = Lotus.list_data_repo_names()
# ["analytics", "main", "reporting", "sqlite_data"]

# Get all configured repositories
all_repos = Lotus.data_repos()
# %{"analytics" => MyApp.AnalyticsRepo, "main" => MyApp.Repo, ...}

# Get a specific repository by name (raises if not found)
repo = Lotus.get_data_repo!("analytics")
# MyApp.AnalyticsRepo
```

> **Note**: The `ecto_repo` can also be included in `data_repos` if you want to run queries against the same database where Lotus stores its data. This is common in single-database applications.

### Behavior Options

#### `unique_names`

Determines whether query names must be unique across all saved queries.

```elixir
config :lotus,
  unique_names: true   # Enforce unique names (recommended)
  # or
  unique_names: false  # Allow duplicate names
```

**Type**: `boolean()`
**Default**: `true`

> **⚠️ Important**: The default Lotus migration creates a unique index on query names. If you want to allow duplicate names (`unique_names: false`), you must remove this constraint from your database.

**To allow duplicate query names:**

1. Set `unique_names: false` in your configuration
2. Create a migration to drop the unique constraint:

```elixir
defmodule MyApp.Repo.Migrations.RemoveLotusUniqueNameConstraint do
  use Ecto.Migration

  def up do
    drop_if_exists(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    create(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
  end

  def down do
    drop_if_exists(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    create(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
  end
end
```

3. Run the migration: `mix ecto.migrate`

#### `table_visibility`

Controls which database tables and schemas can be accessed through Lotus queries. This provides an additional security layer beyond read-only execution.

```elixir
config :lotus,
  table_visibility: %{
    # Default rules apply to all repositories unless overridden
    default: [
      allow: [
        # Allow specific tables
        "users",
        "orders",
        # Allow entire schemas (PostgreSQL)
        {"analytics", ~r/.*/},
        # Allow tables matching pattern
        {"public", ~r/^report_/}
      ],
      deny: [
        # Block specific sensitive tables
        "credit_cards",
        "api_keys",
        # Block tables matching pattern
        {"public", ~r/_internal$/}
      ]
    ],
    # Repository-specific rules override defaults
    analytics: [
      allow: [
        {"analytics", ~r/.*/},
        "users",
        "sessions"
      ]
    ]
  }
```

**Type**: `map()`
**Default**: `%{}`

**Built-in Protection:**

Lotus automatically blocks access to sensitive system tables:

- **PostgreSQL**: `pg_catalog.*`, `information_schema.*`, `schema_migrations`, `lotus_queries`
- **SQLite**: `sqlite_*`, migration tables, `lotus_queries`

**Rule Formats:**

```elixir
# Table name only (for SQLite or default schema)
"users"

# Schema and table (PostgreSQL)
{"public", "users"}

# Pattern matching with regex
{"analytics", ~r/^daily_/}

# Schema-wide rules
{"reporting", ~r/.*/}  # Allow/deny all tables in schema
```

**Rule Evaluation:**

1. **Built-in denials** - System tables are always blocked
2. **Allow rules** - If present, only explicitly allowed tables are accessible
3. **Deny rules** - Explicitly denied tables are blocked
4. **Default behavior** - If no allow rules exist, all non-denied tables are accessible

**Per-Repository Rules:**

You can configure different visibility rules for each data repository:

```elixir
config :lotus,
  data_repos: %{
    "public" => MyApp.PublicRepo,
    "finance" => MyApp.FinanceRepo
  },
  table_visibility: %{
    # Public data - permissive
    public: [
      deny: ["admin_notes", "internal_logs"]
    ],
    # Financial data - very restrictive
    finance: [
      allow: [
        "monthly_revenue_summary",
        "quarterly_reports"
      ]
    ]
  }
```

## Read-Only Repositories (Recommended)

While Lotus provides multiple layers of security including read-only execution and table visibility controls, the ultimate security practice is to use Ecto repositories configured with `read_only: true`. This provides database-level guarantees that no write operations can occur.

### Why Use Read-Only Repositories?

- **Ultimate security**: Repository-level read-only enforcement that cannot be bypassed
- **Zero risk**: Impossible to accidentally perform write operations through the repository
- **Clear intent**: Explicitly declares that a repository is intended only for reading data
- **Additional safety layer**: Works alongside Lotus's existing security features

### Configuring Read-Only Repositories

Ecto provides built-in support for read-only repositories using the `read_only: true` option:

```elixir
# lib/my_app/read_only_repo.ex
defmodule MyApp.ReadOnlyRepo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres,
    read_only: true  # This prevents all write operations at the Ecto level
end
```

Configure Lotus to use your read-only repository for data queries:

```elixir
# config/config.exs
config :lotus,
  ecto_repo: MyApp.Repo,           # Use regular repo for storing Lotus queries
  data_repos: %{
    "main" => MyApp.ReadOnlyRepo,  # Use read-only repo for data queries
    "analytics" => MyApp.AnalyticsReadOnlyRepo
  }

# Configure the read-only repository connection
config :my_app, MyApp.ReadOnlyRepo,
  username: "myapp_user",
  password: "secret",
  hostname: "localhost",
  database: "myapp_prod"
```

### Benefits with Lotus

When you combine Lotus's security features with read-only repositories:

1. **Repository-level enforcement**: The repository cannot execute write operations
2. **Application-level safety**: Lotus still provides SQL validation and table visibility controls
3. **Defense-in-depth**: Multiple layers of protection working together
4. **Peace of mind**: Guaranteed read-only access regardless of SQL content

### Example Usage

```elixir
# This will work - reading data through read-only repo
{:ok, result} = Lotus.run_sql(
  "SELECT COUNT(*) FROM users", 
  [], 
  repo: "main"
)

# This would fail at the repository level even if it somehow bypassed Lotus
# The read-only repository will reject any write operations
```

### Learn More

For comprehensive details on repository configuration options, see the official Ecto documentation: [Replicas and Dynamic Repositories](https://hexdocs.pm/ecto/replicas-and-dynamic-repositories.html).

## Execution Options

While not part of application configuration, Lotus supports runtime options for query execution:

### Timeout Options

```elixir
# Default timeout (5 seconds)
Lotus.run_query(query)

# Custom timeout
Lotus.run_query(query, timeout: 30_000)  # 30 seconds

# Statement-level timeout (PostgreSQL)
Lotus.run_query(query, statement_timeout_ms: 15_000)  # 15 seconds
```

### Connection Options

```elixir
# Use specific schema prefix
Lotus.run_query(query, prefix: "analytics")
```

## Validation

Lotus validates your configuration at startup. Common validation errors:

### Missing Repository

```elixir
# This will raise ArgumentError during compilation
config :lotus
  # repo: MyApp.Repo  # Missing!
```

**Error**: `Invalid :lotus config: required :ecto_repo option not found, received options: []`

## Configuration Helpers

Lotus provides helper functions to access configuration at runtime:

```elixir
# Get the configured repository
Lotus.repo()
# MyApp.Repo

# Check if unique names are enforced
Lotus.unique_names?()
# true
```

## Multi-Database Support

Lotus supports both PostgreSQL and SQLite databases. The migration system automatically detects the adapter and runs the appropriate migrations.

### PostgreSQL Configuration

```elixir
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev",
  pool_size: 10
```

### SQLite Configuration

```elixir
config :my_app, MyApp.SqliteRepo,
  database: Path.expand("../my_app.db", Path.dirname(__ENV__.file)),
  pool_size: 10
```

### Mixed Database Environments

You can mix PostgreSQL and SQLite repositories:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,          # PostgreSQL for storage
  data_repos: %{
    "postgres" => MyApp.Repo,     # PostgreSQL data
    "sqlite" => MyApp.SqliteRepo, # SQLite data
    "analytics" => MyApp.AnalyticsRepo  # Another PostgreSQL
  }
```
