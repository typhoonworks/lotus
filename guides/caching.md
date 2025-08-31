# Caching Guide

This guide covers Lotus's comprehensive caching system, which improves query performance by storing and reusing results from expensive database operations.

## Overview

Lotus provides a flexible caching system with the following features:

- **Pluggable adapters** - Support for different cache backends (currently only ETS supported)
- **TTL-based expiration** - Automatic cache invalidation based on time-to-live
- **Cache profiles** - Different caching strategies for different use cases
- **Tag-based invalidation** - Selective cache clearing using tags
- **Multiple cache modes** - Fine-grained control over cache behavior
- **Namespace support** - Cache isolation and organization

## Quick Start

### Basic Configuration

Add caching to your Lotus configuration:

```elixir
# config/config.exs
config :lotus,
  ecto_repo: MyApp.Repo,
  data_repos: %{
    "main" => MyApp.Repo
  },
  cache: [
    adapter: Lotus.Cache.ETS,
    namespace: "myapp_lotus"
  ]
```

### OTP Application Setup

**Important**: For caching to work in production, Lotus must be started as part of your application's supervision tree. Cache backends are supervised processes that need to be running.

Add Lotus to your application supervisor:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    # Add Lotus to your supervision tree
    Lotus,
    # Or with custom options:
    # {Lotus, cache: [adapter: Lotus.Cache.ETS, namespace: "prod_cache"]},
    MyAppWeb.Endpoint
  ]
  
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Using Cache in Queries

Once configured and started, caching works automatically:

```elixir
# First call - executes query and caches result
{:ok, result1} = Lotus.run_sql("SELECT COUNT(*) FROM users")

# Second call - returns cached result (much faster!)
{:ok, result2} = Lotus.run_sql("SELECT COUNT(*) FROM users")
```

## Configuration

### Cache Adapter

Currently, Lotus supports one cache adapter:

#### ETS Adapter

The `Lotus.Cache.ETS` adapter provides in-memory caching using Erlang Term Storage (ETS):

```elixir
config :lotus,
  cache: [
    adapter: Lotus.Cache.ETS,
    namespace: "myapp_lotus",    # Optional namespace
    max_bytes: 5_000_000,       # Max entry size: 5MB (default)
    compress: true              # Compress cache entries (default: true)
  ]
```

**Characteristics:**
- **Performance**: Very fast reads and writes
- **Persistence**: In-memory only (data lost on application restart)
- **Scalability**: Single-node only (not distributed)
- **TTL**: Automatic expiration with background cleanup
- **Size limits**: Entries exceeding `max_bytes` are automatically rejected

### Cache Profiles

Profiles allow you to configure different TTL strategies for different types of queries:

```elixir
config :lotus,
  cache: [
    adapter: Lotus.Cache.ETS,
    profiles: %{
      results: [ttl_ms: 30_000],      # 30 seconds - fast-changing data
      options: [ttl_ms: 300_000],     # 5 minutes - dropdown options
      schema: [ttl_ms: 3_600_000],    # 1 hour - table schemas
      reports: [ttl_ms: 1_800_000]    # 30 minutes - business reports
    },
    default_profile: :results,        # Used when no profile specified
    default_ttl_ms: 60_000           # 1 minute - fallback TTL
  ]
```

### Namespace Support

Namespaces provide cache isolation and organization:

```elixir
config :lotus,
  cache: [
    adapter: Lotus.Cache.ETS,
    namespace: "myapp_lotus"  # Optional namespace for cache isolation
  ]
```

## Cache Modes

Lotus provides three cache modes for different scenarios:

### Default Mode (Automatic Caching)

When no cache mode is specified, Lotus automatically caches results:

```elixir
# Uses cache if available, otherwise queries database and caches result
{:ok, result} = Lotus.run_sql("SELECT * FROM products")
```

### Bypass Mode

Skip cache entirely - always query the database:

```elixir
# Always hits database, never reads from or writes to cache
{:ok, result} = Lotus.run_sql("SELECT * FROM products", [], cache: :bypass)
```

**Use cases:**
- Real-time data requirements
- Testing scenarios
- One-off queries where cache isn't beneficial

### Refresh Mode

Execute query and update cache with fresh results:

```elixir
# Executes query AND updates cache with new result
{:ok, result} = Lotus.run_sql("SELECT * FROM products", [], cache: :refresh)
```

**Use cases:**
- Force cache refresh after data changes
- Scheduled cache warming
- Manual cache updates

## Cache Options

### Profile Selection

Choose a specific cache profile for a query:

```elixir
# Use the 'schema' profile (longer TTL)
{:ok, tables} = Lotus.run_sql("SELECT name FROM sqlite_master", [], cache: [profile: :schema])
```

### TTL Override

Override the default TTL for specific queries:

```elixir
# Cache for exactly 2 minutes regardless of profile
{:ok, result} = Lotus.run_sql("SELECT * FROM users", [], cache: [ttl_ms: 120_000])
```

### Tag-Based Caching

Tag cache entries for selective invalidation:

```elixir
# Tag this cache entry
{:ok, user} = Lotus.run_sql("SELECT * FROM users WHERE id = $1", [123],
  cache: [tags: ["user:123", "user_data"]])

# Later, invalidate all entries with these tags
Lotus.Cache.invalidate_tags(["user:123"])
```

### Combined Options

You can combine multiple cache options:

```elixir
{:ok, result} = Lotus.run_sql("SELECT * FROM products", [],
  cache: [
    profile: :reports,
    ttl_ms: 600_000,  # Override profile TTL
    tags: ["products", "inventory"]
  ])
```

## Cache Key Generation

Lotus generates cache keys based on:

- **SQL statement** - The actual query text
- **Parameters** - Query parameters and variable values
- **Repository** - Which database the query targets
- **Search path** - PostgreSQL schema search path
- **Lotus version** - Ensures cache invalidation across version upgrades

This ensures that different queries, even with slight variations, get separate cache entries.

## Schema Function Caching

All Lotus schema introspection functions are automatically cached:

- `Lotus.list_tables/2` - Lists tables and views in database
- `Lotus.get_table_schema/3` - Gets column information for tables  
- `Lotus.get_table_stats/3` - Gets row counts and table statistics
- `Lotus.list_relations/2` - Lists tables with schema information

### Default Cache Behavior

Schema functions use different cache profiles by default:

```elixir
# Schema metadata - uses :schema profile (1 hour TTL)
{:ok, tables} = Lotus.list_tables("postgres")
{:ok, schema} = Lotus.get_table_schema("postgres", "users")
{:ok, relations} = Lotus.list_relations("postgres")

# Table statistics - uses :results profile (30 seconds TTL)  
{:ok, stats} = Lotus.get_table_stats("postgres", "users")
```

**Why different profiles?**
- **Schema metadata** (tables, columns) changes rarely, so longer caching (1 hour) is safe
- **Table statistics** (row counts) change frequently, so shorter caching (30 seconds) keeps data fresh

### Schema Cache Options

Schema functions support all cache modes and options:

```elixir
# Bypass cache for fresh data
{:ok, tables} = Lotus.list_tables("postgres", cache: :bypass)

# Refresh cache with latest data  
{:ok, schema} = Lotus.get_table_schema("postgres", "users", cache: :refresh)

# Use custom profile
{:ok, stats} = Lotus.get_table_stats("postgres", "users", 
  cache: [profile: :options])  # 5 minute TTL

# Override TTL
{:ok, relations} = Lotus.list_relations("postgres",
  cache: [ttl_ms: 600_000])  # 10 minutes

# Add tags for invalidation
{:ok, schema} = Lotus.get_table_schema("postgres", "products",
  cache: [tags: ["schema:products", "metadata"]])
```

### Schema Cache Invalidation

Schema information is automatically tagged for selective invalidation:

```elixir
# After schema changes (migrations, table creation, etc.)
Lotus.Cache.invalidate_tags(["repo:postgres", "schema:list_tables"])

# After specific table changes
Lotus.Cache.invalidate_tags(["table:public.users"])
```

**Automatic tags added:**
- `"repo:#{repo_name}"` - Repository-specific data
- `"schema:#{function_name}"` - Function-specific data  
- `"table:#{schema}.#{table}"` - Table-specific data (when applicable)

## Working with run_query

Saved queries (`run_query`) support all the same cache options:

```elixir
# Automatic caching based on configuration
{:ok, result} = Lotus.run_query(query_id)

# Bypass cache
{:ok, result} = Lotus.run_query(query_id, cache: :bypass)

# Use specific profile
{:ok, result} = Lotus.run_query(query_id, cache: [profile: :reports])

# Tag for invalidation
{:ok, result} = Lotus.run_query(query_id,
  cache: [tags: ["query:#{query_id}", "dashboard"]])
```

## Cache Management

### Manual Cache Invalidation

Invalidate cache entries by tags:

```elixir
# Invalidate specific entries
Lotus.Cache.invalidate_tags(["user:123"])

# Invalidate multiple tags
Lotus.Cache.invalidate_tags(["user_data", "reports", "dashboard"])
```

### Automatic Tagging

Lotus automatically adds these tags to cached entries:

- `"query:#{query_id}"` - For run_query calls
- `"repo:#{repo_name}"` - For the database repository used
- `"schema:#{function_name}"` - For Schema function calls (list_tables, get_table_schema, etc.)
- `"table:#{schema}.#{table}"` - For table-specific Schema operations

You can add your own tags in addition to these automatic ones.

## Performance Considerations

### Cache Effectiveness

Monitor cache effectiveness by observing query performance improvements and application response times. Future versions may include cache statistics and telemetry integration.

### Memory Usage

ETS cache memory grows with cached data. Consider:

- **Appropriate TTLs** - Don't cache data longer than needed
- **Selective caching** - Use `:bypass` for large result sets that aren't reused
- **Size limits** - Large cache entries are automatically rejected (default: 5MB, configurable)
- **Regular cleanup** - TTL-based expiration handles this automatically

### Cache Warming

Pre-populate cache with commonly used queries:

```elixir
# During application startup or scheduled jobs
{:ok, _} = Lotus.run_sql("SELECT * FROM lookup_tables", [], cache: :refresh)
{:ok, _} = Lotus.run_query(dashboard_query_id, cache: :refresh)
```

## Best Practices

### Profile Strategy

```elixir
config :lotus,
  cache: [
    profiles: %{
      # Fast-changing transactional data
      results: [ttl_ms: 30_000],      # 30 seconds

      # Reference data that changes occasionally
      options: [ttl_ms: 300_000],     # 5 minutes

      # Schema information that rarely changes
      schema: [ttl_ms: 3_600_000],    # 1 hour

      # Business reports with longer acceptable staleness
      reports: [ttl_ms: 1_800_000]    # 30 minutes
    }
  ]
```

### Tagging Strategy

```elixir
# User-specific data
cache: [tags: ["user:#{user_id}", "user_data"]]

# Feature-specific data
cache: [tags: ["dashboard", "reports"]]

# Entity-specific data
cache: [tags: ["product:#{product_id}", "inventory"]]
```

### When to Use Each Mode

- **Default mode**: Most queries - let cache system optimize automatically
- **`:bypass` mode**: Real-time data, large one-off queries, testing
- **`:refresh` mode**: After data updates, scheduled cache warming, manual refresh

### Cache Invalidation

```elixir
# After updating user data
User.update(user, %{name: "New Name"})
Lotus.Cache.invalidate_tags(["user:#{user.id}"])

# After bulk data updates
Products.bulk_update()
Lotus.Cache.invalidate_tags(["products", "inventory"])

# After schema changes (migrations, DDL operations)
Ecto.Migrator.run(MyApp.Repo, :up, all: true)
Lotus.Cache.invalidate_tags(["repo:postgres", "schema:list_tables"])

# After table-specific changes
alter table(:users) do
  add :new_column, :string
end
Lotus.Cache.invalidate_tags(["table:public.users"])
```

## Troubleshooting

### Cache Not Working

1. **Check OTP setup**: Ensure Lotus is started in your supervision tree - cache backends need to be running
2. **Check configuration**: Ensure cache adapter is properly configured
3. **Verify identical queries**: Cache keys are generated from exact SQL + params
4. **Check TTL**: Ensure cache hasn't expired between calls

**Common Error**: `** (ArgumentError) argument error` or `:noproc` errors usually indicate the cache backend process isn't running. Add Lotus to your application's supervision tree.

### Memory Issues

1. **Review TTL settings**: Shorter TTLs = less memory usage
2. **Use selective caching**: Don't cache large result sets unnecessarily
3. **Monitor cache size**: Check ETS table memory usage

### Performance Issues

1. **Cache hit ratio**: Low hit ratio may indicate poor cache strategy
2. **TTL tuning**: Balance between data freshness and cache effectiveness
3. **Query optimization**: Cache works best with optimized queries
