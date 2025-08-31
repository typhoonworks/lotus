# Configuration

This guide covers all configuration options available in Lotus and how to customize the library for your specific needs.

## Basic Configuration

Lotus configuration is typically placed in your `config/config.exs` file:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,        # Repository for Lotus query storage
  default_repo: "main",         # Default repository for query execution
  data_repos: %{                # Repositories for executing queries
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  },
  cache: [                      # Optional caching configuration
    adapter: Lotus.Cache.ETS,   # Cache adapter (currently only ETS supported)
    namespace: "myapp_cache"    # Cache namespace (optional)
  ]
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

A map of repositories where queries can be executed against actual data. This powerful feature allows Lotus to work with multiple databases simultaneously, supporting PostgreSQL, MySQL, and SQLite.

Keys are friendly names that you use when executing queries, values are Ecto repository modules.

```elixir
config :lotus,
  data_repos: %{
    "main" => MyApp.Repo,           # Can be the same as ecto_repo
    "analytics" => MyApp.AnalyticsRepo,
    "reporting" => MyApp.ReportingRepo,
    "mysql_data" => MyApp.MySQLRepo,    # MySQL repository
    "sqlite_data" => MyApp.SqliteRepo   # Mix database types
  }
```

**Type**: `%{String.t() => module()}`

#### `default_repo` (required when multiple data_repos)

When you have multiple data repositories configured, you must specify which one to use by default when no explicit repository is provided in query execution.

```elixir
config :lotus,
  default_repo: "main",  # Must match a key in data_repos
  data_repos: %{
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

**Type**: `String.t()`
**Default**: Not required if only one data repository is configured

**Behavior**:
- **Single repo**: When only one data repository is configured, it's automatically used as the default
- **Multiple repos**: You must configure `default_repo` to specify which one to use when no repo is explicitly provided
- **No repos**: Raises an error if no data repositories are configured

**Usage Examples:**

```elixir
# Execute against a specific repository by name
Lotus.run_sql("SELECT COUNT(*) FROM users", [], repo: "analytics")

# Execute against a repository module directly
Lotus.run_sql("SELECT COUNT(*) FROM users", [], repo: MyApp.AnalyticsRepo)

# When no repo is specified, uses the configured default_repo
Lotus.run_sql("SELECT COUNT(*) FROM users")  # Uses "main" repo from default_repo config
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

### Optional Features

#### `cache`

Configures result caching to improve query performance. When enabled, Lotus automatically caches query results and reuses them for identical queries.

```elixir
config :lotus,
  cache: [
    adapter: Lotus.Cache.ETS,         # Cache adapter (required)
    namespace: "myapp_cache",         # Cache namespace (optional)
    max_bytes: 5_000_000,            # Max cache entry size: 5MB (default)
    compress: true,                   # Compress cache entries (default)
    profiles: %{                      # Cache profiles with different TTL strategies
      results: [ttl_ms: 30_000],     # Short-term results (30 seconds)
      options: [ttl_ms: 300_000],    # Medium-term data (5 minutes)  
      schema: [ttl_ms: 3_600_000]    # Long-term schema info (1 hour)
    },
    default_profile: :results,        # Default profile when none specified
    default_ttl_ms: 60_000           # Fallback TTL (1 minute)
  ]
```

**Type**: `keyword()`  
**Default**: `nil` (no caching)

**Available Adapters:**
- `Lotus.Cache.ETS` - In-memory caching using ETS tables

**Cache Modes:**
- **Default**: Automatic caching when cache is configured
- **`:bypass`**: Skip cache entirely, always query database
- **`:refresh`**: Execute query and update cache with fresh results

For detailed caching configuration and usage, see the [Caching Guide](caching.md).

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
        # Allow specific tables in all schemas
        "users",                      # Allow 'users' table in any schema
        "orders",                     # Allow 'orders' table in any schema
        # Allow entire schemas (PostgreSQL)
        {"analytics", ~r/.*/},        # All tables in analytics schema
        # Allow tables matching pattern in specific schema
        {"public", ~r/^report_/}      # Tables starting with 'report_' in public
      ],
      deny: [
        # Block sensitive tables across ALL schemas
        "credit_cards",               # Blocks credit_cards in any schema
        "api_keys",                   # Blocks api_keys in any schema  
        # Block tables in specific schema only
        {"public", "internal_logs"},  # Only blocks public.internal_logs
        # Block pattern in specific schema
        {"public", ~r/_internal$/}    # Tables ending with '_internal' in public
      ]
    ],
    # Repository-specific rules override defaults
    analytics: [
      allow: [
        {"analytics", ~r/.*/},        # All tables in analytics schema
        "users",                      # users table in any schema
        "sessions"                    # sessions table in any schema
      ]
    ]
  }
```

**Type**: `map()`
**Default**: `%{}`

**Built-in Protection:**

Lotus automatically blocks access to sensitive system tables:

- **PostgreSQL**: `pg_catalog.*`, `information_schema.*`, `schema_migrations`, `lotus_queries`
- **MySQL**: `information_schema.*`, `mysql.*`, `performance_schema.*`, `sys.*`, `schema_migrations`, `lotus_queries`
- **SQLite**: `sqlite_*`, migration tables, `lotus_queries`

**Rule Formats:**

```elixir
# Bare string - matches table name in ANY schema (PostgreSQL) or no schema (SQLite)
"users"                        # Blocks/allows 'users' table in all schemas
"api_keys"                     # Blocks/allows 'api_keys' in public, reporting, etc.

# Schema-specific tuple (PostgreSQL only)
{"public", "users"}            # Only affects public.users
{"reporting", "api_keys"}      # Only affects reporting.api_keys

# Pattern matching with regex
{"analytics", ~r/^daily_/}     # Tables starting with 'daily_' in analytics schema
~r/^temp_/                     # Tables starting with 'temp_' in any schema (as bare regex)

# Schema-wide rules
{"reporting", ~r/.*/}          # All tables in reporting schema
{~r/test_/, ~r/.*/}           # All tables in schemas starting with 'test_'
```

> **Note**: Bare strings like `"api_keys"` are the simplest way to block sensitive tables across all schemas. Use tuples like `{"public", "api_keys"}` when you need schema-specific control.

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
# Use search_path for schema resolution
Lotus.run_query(query, search_path: "analytics, public")
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

Lotus supports PostgreSQL, MySQL, and SQLite databases. The migration system automatically detects the adapter and runs the appropriate migrations.

### PostgreSQL Configuration

```elixir
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev",
  pool_size: 10
```

### MySQL Configuration

```elixir
config :my_app, MyApp.MySQLRepo,
  username: "root",
  password: "mysql",
  hostname: "localhost",
  port: 3306,
  database: "my_app_dev",
  pool_size: 10
```

### SQLite Configuration

**Security Note**: SQLite 3.8.0+ (2013) provides enhanced security through `PRAGMA query_only`, which prevents write operations at the database engine level.

```elixir
config :my_app, MyApp.SqliteRepo,
  database: Path.expand("../my_app.db", Path.dirname(__ENV__.file)),
  pool_size: 10
```

### Mixed Database Environments

You can mix PostgreSQL, MySQL, and SQLite repositories:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,          # PostgreSQL for storage
  default_repo: "postgres",       # Default repository for queries
  data_repos: %{
    "postgres" => MyApp.Repo,     # PostgreSQL data
    "mysql" => MyApp.MySQLRepo,   # MySQL data
    "sqlite" => MyApp.SqliteRepo, # SQLite data
    "analytics" => MyApp.AnalyticsRepo  # Another PostgreSQL
  }
```
