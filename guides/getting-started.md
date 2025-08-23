# Getting Started

This guide will walk you through your first steps with Lotus, from creating your first query to understanding the results.

## Prerequisites

Before starting, make sure you have:

- Completed the [Installation](installation.md) guide
- A running Elixir application with Ecto and Lotus configured
- Some data in your database to query

## Your First Query

### Creating a Saved Query

Let's create and save a simple query:

```elixir
# Create a new query
{:ok, query} = Lotus.create_query(%{
  name: "Count Users",
  query: %{
    sql: "SELECT COUNT(*) as user_count FROM users"
  }
})

IO.inspect(query)
# %Lotus.Storage.Query{
#   id: 1,
#   name: "Count Users",
#   statement: "SELECT COUNT(*) as user_count FROM users",
#   inserted_at: ~N[2024-01-15 10:30:00],
#   updated_at: ~N[2024-01-15 10:30:00]
# }
```

### Running the Query

Now let's execute our saved query:

```elixir
# Execute the saved query
{:ok, result} = Lotus.run_query(query)

IO.inspect(result)
# %Lotus.QueryResult{
#   columns: ["user_count"],
#   rows: [[42]],
#   num_rows: 1
# }
```

### Accessing Results

The `QueryResult` struct contains all the information about your query execution:

```elixir
# Get the column names
result.columns
# ["user_count"]

# Get the data rows
result.rows
# [[42]]

# Get the number of rows returned
result.num_rows
# 1

# The QueryResult struct contains:
# - columns: list of column names
# - rows: list of result rows
# - num_rows: total count of returned rows
```

## Ad-hoc Queries

Sometimes you want to run a query without saving it first:

```elixir
# Run SQL directly
{:ok, result} = Lotus.run_sql(
  "SELECT name, email FROM users WHERE active = $1 LIMIT $2",
  [true, 10]
)

IO.inspect(result.columns)
# ["name", "email"]

IO.inspect(result.rows)
# [
#   ["Alice Johnson", "alice@example.com"],
#   ["Bob Smith", "bob@example.com"],
#   ...
# ]
```

## Working with Multiple Data Repositories

If you have configured multiple data repositories, you can execute queries against specific databases:

```elixir
# Execute against a specific repository by name
{:ok, result} = Lotus.run_sql(
  "SELECT COUNT(*) FROM page_views WHERE date = $1",
  [Date.utc_today()],
  repo: "analytics"
)

# Execute against a repository module directly
{:ok, result} = Lotus.run_sql(
  "SELECT SUM(amount) FROM transactions",
  [],
  repo: MyApp.SqliteRepo
)

# List all available data repositories
repo_names = Lotus.list_data_repo_names()
IO.inspect(repo_names)
# ["main", "analytics", "sqlite_data"]
```

### Storing Queries with Specific Data Repositories

You can store queries with a specific data repository, so they automatically execute against the correct database:

```elixir
# Create a query that will run against the analytics database
{:ok, analytics_query} = Lotus.create_query(%{
  name: "Daily Page Views",
  query: %{
    sql: "SELECT COUNT(*) FROM page_views WHERE date = $1",
    params: [Date.utc_today()]
  },
  data_repo: "analytics"
})

# Create a query for the main database
{:ok, user_query} = Lotus.create_query(%{
  name: "Active Users",
  statement: "SELECT COUNT(*) FROM users WHERE active = true",
  data_repo: "main"
})

# Execute queries - they automatically use their stored data_repo
{:ok, analytics_result} = Lotus.run_query(analytics_query)
{:ok, user_result} = Lotus.run_query(user_query)
```

### Runtime Repository Override

You can override the stored data repository at execution time:

```elixir
# Query was saved with data_repo: "analytics"
{:ok, query} = Lotus.create_query(%{
  name: "User Count",
  statement: "SELECT COUNT(*) FROM users",
  data_repo: "analytics"
})

# Execute against the stored repository
{:ok, result} = Lotus.run_query(query)

# Override at runtime to use a different repository
{:ok, result} = Lotus.run_query(query, repo: "main")
```

### Fallback Behavior

If you don't specify a `data_repo` when creating a query, it will use the default repository when executed:

```elixir
# Query without specific data_repo
{:ok, query} = Lotus.create_query(%{
  name: "Generic Query",
  statement: "SELECT 1"
  # No data_repo specified
})

# Will use the default configured repository
{:ok, result} = Lotus.run_query(query)
```

## Managing Saved Queries

### Listing All Queries

```elixir
# Get all saved queries
queries = Lotus.list_queries()

Enum.each(queries, fn query ->
  IO.puts("#{query.id}: #{query.name}")
end)
# 1: Count Users
# 2: Active Users Report
# 3: Monthly Sales Summary
```

### Finding a Specific Query

```elixir
# Get a query by ID
query = Lotus.get_query!(1)
IO.puts(query.name)
# "Count Users"
```

### Updating a Query

```elixir
# Update an existing query
{:ok, updated_query} = Lotus.update_query(query, %{
  name: "Total User Count",
  query: %{
    sql: "SELECT COUNT(*) as total_users FROM users WHERE deleted_at IS NULL"
  }
})

IO.puts(updated_query.name)
# "Total User Count"
```

### Deleting a Query

```elixir
# Delete a query
{:ok, _deleted_query} = Lotus.delete_query(query)

# Verify it's gone
try do
  Lotus.get_query!(query.id)
rescue
  Ecto.NoResultsError -> IO.puts("Query deleted successfully")
end
```

## PostgreSQL Schema Resolution with search_path

When working with PostgreSQL databases that use multiple schemas, you can use `search_path` to resolve unqualified table names. This is especially useful for multi-tenant applications or when you have separate schemas for reporting, analytics, or different environments.

### Understanding search_path

PostgreSQL's `search_path` determines which schemas are searched when you reference an unqualified table name like `users` instead of `reporting.users`. For example:

```elixir
# Without search_path - must fully qualify table names
{:error, reason} = Lotus.run_sql("SELECT * FROM customers")
# "SQL error: relation \"customers\" does not exist"

# With search_path - finds reporting.customers automatically
{:ok, result} = Lotus.run_sql(
  "SELECT * FROM customers", 
  [], 
  search_path: "reporting, public"
)
```

### Stored Queries with search_path

You can save a `search_path` with your queries to make them automatically resolve against the correct schemas:

```elixir
# Create a query that looks in reporting schema first, then public
{:ok, query} = Lotus.create_query(%{
  name: "Customer Report",
  query: %{
    sql: "SELECT COUNT(*) FROM customers WHERE active = true",
    params: []
  },
  search_path: "reporting, public",
  data_repo: "postgres"
})

# Execute - automatically uses the stored search_path
{:ok, result} = Lotus.run_query(query)
# Finds reporting.customers without needing to qualify the table name
```

### Runtime search_path Override

You can override or provide a `search_path` at runtime:

```elixir
# Override stored search_path
{:ok, result} = Lotus.run_query(query, search_path: "analytics, public")

# Provide search_path for ad-hoc queries
{:ok, result} = Lotus.run_sql(
  "SELECT u.name, o.total FROM users u JOIN orders o ON u.id = o.user_id",
  [],
  repo: "postgres",
  search_path: "reporting, public"
)
```

### Multi-Schema Scenarios

Here are common patterns for using `search_path`:

#### Multi-Tenant with Schema-per-Tenant

```elixir
# Query template that works across tenant schemas
{:ok, tenant_query} = Lotus.create_query(%{
  name: "Tenant User Count",
  statement: "SELECT COUNT(*) FROM users WHERE active = {is_active}",
  var_defaults: %{"is_active" => true},
  data_repo: "postgres"
})

# Execute for different tenants by overriding search_path
{:ok, tenant_a_result} = Lotus.run_query(tenant_query, search_path: "tenant_123, public")
{:ok, tenant_b_result} = Lotus.run_query(tenant_query, search_path: "tenant_456, public") 
```

#### Reporting and Analytics Schemas

```elixir
# Create queries that work across different schema contexts
{:ok, report_query} = Lotus.create_query(%{
  name: "Monthly Revenue",
  query: %{
    sql: """
    SELECT 
      DATE_TRUNC('month', created_at) as month,
      SUM(amount) as revenue
    FROM orders 
    WHERE created_at >= $1 
    GROUP BY 1 
    ORDER BY 1
    """
  },
  search_path: "reporting, public",
  data_repo: "postgres"
})

# Use the same query structure for different contexts
{:ok, prod_data} = Lotus.run_query(report_query, [~D[2024-01-01]])
{:ok, staging_data} = Lotus.run_query(report_query, [~D[2024-01-01]], search_path: "staging, public")
```

#### Mixed Schema Access

```elixir
# Query that needs tables from multiple schemas in search order
{:ok, complex_query} = Lotus.create_query(%{
  name: "User Activity Summary", 
  query: %{
    sql: """
    SELECT 
      u.name,
      COUNT(e.id) as event_count,
      MAX(s.last_login) as last_seen
    FROM users u
    LEFT JOIN events e ON u.id = e.user_id  -- from analytics schema
    LEFT JOIN sessions s ON u.id = s.user_id  -- from public schema
    GROUP BY u.id, u.name
    """
  },
  search_path: "public, analytics",  # users in public, events in analytics
  data_repo: "postgres"
})
```

### search_path Validation

Lotus validates `search_path` values to prevent injection attacks:

```elixir
# Valid search_path values
{:ok, query} = Lotus.create_query(%{
  name: "Valid Query",
  statement: "SELECT 1",
  search_path: "reporting"  # single schema
})

{:ok, query} = Lotus.create_query(%{
  name: "Valid Query",  
  statement: "SELECT 1",
  search_path: "schema1, schema_2, public"  # multiple schemas
})

# Invalid search_path - validation error
{:error, changeset} = Lotus.create_query(%{
  name: "Invalid Query",
  statement: "SELECT 1", 
  search_path: "invalid-name, 123schema"  # hyphens and leading numbers not allowed
})

errors_on(changeset)
# %{search_path: ["must be a comma-separated list of identifiers"]}
```

### search_path with Other Databases

For non-PostgreSQL databases, `search_path` is safely ignored:

```elixir
# SQLite ignores search_path without error
{:ok, result} = Lotus.run_sql(
  "SELECT COUNT(*) FROM products",
  [],
  repo: "sqlite",
  search_path: "ignored_value"  # Has no effect but doesn't cause errors
)
```

### Safety and Scoping

Lotus implements `search_path` safely:

- Uses `SET LOCAL search_path` to scope changes to the current transaction only
- Changes don't leak to other queries or database sessions  
- The same `search_path` is used for both preflight authorization and query execution
- Schema identifiers are validated to prevent injection attacks

## Working with Smart Variables

Lotus supports smart variable substitution using `{var}` placeholders for safety and reusability:

```elixir
# Create a query with smart variables
{:ok, query} = Lotus.create_query(%{
  name: "Users by Status",
  statement: "SELECT id, name, email FROM users WHERE status = {status} AND created_at > {created_date}",
  var_defaults: %{
    "status" => "active",
    "created_date" => ~D[2024-01-01]
  }
})

# Run with the default variables
{:ok, result} = Lotus.run_query(query)

# Override variables at runtime
{:ok, result} = Lotus.run_query(query, vars: %{
  "status" => "pending",
  "created_date" => ~D[2024-06-01]
})
```

### Variable Features

- **Safe substitution**: Variables are converted to database-specific placeholders (`$1, $2` for PostgreSQL, `?` for SQLite)
- **Default values**: Use `var_defaults` to provide fallback values
- **Runtime override**: Pass `vars:` option to override defaults
- **Multiple occurrences**: The same variable can appear multiple times and will be bound correctly
- **Type safety**: Variables are passed as parameters, preventing SQL injection

## Error Handling

Lotus provides clear error messages for common issues:

```elixir
# Invalid SQL
{:error, reason} = Lotus.run_sql("SELCT * FROM users")  # typo in SELECT
IO.inspect(reason)
# "SQL syntax error: syntax error at or near \"SELCT\""

# Attempting destructive operation
{:error, reason} = Lotus.run_sql("DROP TABLE users")
IO.inspect(reason)
# "Only read-only queries are allowed"

# Query timeout
{:error, reason} = Lotus.run_sql(
  "SELECT pg_sleep(10)",
  [],
  timeout: 1000  # 1 second timeout
)
IO.inspect(reason)
# "SQL error: canceling statement due to user request"

# Table visibility restriction
{:error, reason} = Lotus.run_sql("SELECT * FROM schema_migrations")
IO.inspect(reason)
# "Query touches blocked table(s): schema_migrations"
```

## Configuration Options

You can customize query execution with options:

```elixir
# Set a custom timeout
{:ok, result} = Lotus.run_query(query, timeout: 30_000)

# Use a search_path for schema resolution
{:ok, result} = Lotus.run_query(query, search_path: "reporting, public")

# Combine multiple options
{:ok, result} = Lotus.run_query(query, [
  timeout: 30_000,
  search_path: "reporting, public",
  statement_timeout_ms: 25_000
])
```

## Best Practices

### 1. Use Descriptive Names

```elixir
# Good
Lotus.create_query(%{
  name: "Monthly Active Users Report",
  query: %{sql: "..."}
})

# Avoid
Lotus.create_query(%{
  name: "Query 1",
  query: %{sql: "..."}
})
```

### 2. Always Use Parameters for Dynamic Values

```elixir
# Good - safe from SQL injection
Lotus.run_sql(
  "SELECT * FROM users WHERE status = $1",
  [user_status]
)

# Avoid - vulnerable to SQL injection
Lotus.run_sql("SELECT * FROM users WHERE status = '#{user_status}'")
```

### 3. Handle Errors Gracefully

```elixir
case Lotus.run_query(query) do
  {:ok, result} ->
    process_results(result)

  {:error, reason} ->
    Logger.error("Query failed: #{inspect(reason)}")
    {:error, "Unable to generate report"}
end
```

## Next Steps

Now that you understand the basics, explore:

- [Configuration](configuration.md) - Learn about all available configuration options
