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
#   query: %{"sql" => "SELECT COUNT(*) as user_count FROM users"},
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

## Working with Parameters

Lotus supports parameterized queries for safety and reusability:

```elixir
# Create a parameterized query
{:ok, query} = Lotus.create_query(%{
  name: "Users by Status",
  query: %{
    sql: "SELECT id, name, email FROM users WHERE status = $1 AND created_at > $2",
    params: ["active", ~D[2024-01-01]]
  }
})

# Run with the stored parameters
{:ok, result} = Lotus.run_query(query)
```

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

# Use a specific schema prefix
{:ok, result} = Lotus.run_query(query, prefix: "analytics")

# Combine multiple options
{:ok, result} = Lotus.run_query(query, [
  timeout: 30_000,
  prefix: "reporting",
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
