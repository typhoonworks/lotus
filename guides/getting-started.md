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
# %Lotus.Result{
#   columns: ["user_count"],
#   rows: [[42]],
#   num_rows: 1
# }
```

### Accessing Results

The `Result` struct contains all the information about your query execution:

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

# The Result struct contains:
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

Lotus supports PostgreSQL, MySQL, and SQLite databases. If you have configured multiple data repositories, you can execute queries against specific databases:

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
  repo: MyApp.MySQLRepo
)

# List all available data repositories
repo_names = Lotus.list_data_repo_names()
IO.inspect(repo_names)
# ["postgres", "mysql", "sqlite", "analytics"]
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

### Default Repository Behavior

If you don't specify a `data_repo` when creating a query, it will use the configured `default_repo` when executed:

```elixir
# Configuration with default_repo
config :lotus,
  default_repo: "main",
  data_repos: %{
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }

# Query without specific data_repo
{:ok, query} = Lotus.create_query(%{
  name: "Generic Query",
  statement: "SELECT 1"
  # No data_repo specified
})

# Will use the "main" repository (from default_repo config)
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

## Working with Visualizations

Lotus supports saving chart configurations (visualizations) alongside your queries. Visualizations use a renderer-agnostic DSL that can be transformed by frontend applications like Lotus Web into concrete chart specs (Vega-Lite, Recharts, etc.).

### Creating a Visualization

```elixir
# First, create or get a query
{:ok, query} = Lotus.create_query(%{
  name: "Monthly Revenue",
  statement: "SELECT date_trunc('month', created_at) as month, SUM(amount) as revenue, region FROM orders GROUP BY 1, 2"
})

# Create a visualization for the query
{:ok, viz} = Lotus.create_visualization(query, %{
  name: "Revenue by Region",
  position: 0,
  config: %{
    "chart" => "line",
    "x" => %{"field" => "month", "kind" => "temporal", "timeUnit" => "month"},
    "y" => [%{"field" => "revenue", "agg" => "sum"}],
    "series" => %{"field" => "region"},
    "options" => %{"legend" => true}
  }
})

IO.inspect(viz)
# %Lotus.Storage.QueryVisualization{
#   id: 1,
#   query_id: 1,
#   name: "Revenue by Region",
#   position: 0,
#   config: %{...},
#   version: 1
# }
```

### Visualization Config DSL

Lotus stores visualization configs as opaque maps, giving you full flexibility. The structure below is the recommended format used by Lotus Web, but you can store any valid map that suits your charting library.

The config uses a neutral format that maps to common charting concepts:

```elixir
%{
  # Chart type (required)
  "chart" => "line",  # line | bar | area | scatter | table | number | heatmap

  # X-axis configuration (optional)
  "x" => %{
    "field" => "month",           # Column name from query results
    "kind" => "temporal",         # temporal | quantitative | nominal
    "timeUnit" => "month"         # Optional: year | quarter | month | week | day
  },

  # Y-axis configuration (optional, list of fields)
  "y" => [
    %{"field" => "revenue", "agg" => "sum"},   # agg: sum | avg | count
    %{"field" => "cost", "agg" => "sum"}
  ],

  # Series/color grouping (optional)
  "series" => %{"field" => "region"},

  # Client-side filters (optional)
  "filters" => [
    %{"field" => "region", "op" => "=", "value" => "EMEA"}  # op: = | != | < | <= | > | >= | in | not in
  ],

  # Display options (optional)
  "options" => %{
    "legend" => true,
    "stack" => "none"  # none | stack | normalize
  }
}
```

### Listing Visualizations

```elixir
# Get all visualizations for a query (ordered by position)
visualizations = Lotus.list_visualizations(query.id)

Enum.each(visualizations, fn viz ->
  IO.puts("#{viz.position}: #{viz.name} (#{viz.config["chart"]})")
end)
# 0: Revenue by Region (line)
# 1: Revenue Table (table)
```

### Validating Against Query Results

Lotus provides optional validation to check that your config references valid columns from the query results. This validation does **not** enforce any particular config structure—it only checks field references.

```elixir
# Run the query to get results
{:ok, result} = Lotus.run_query(query)

# Validate the visualization config
config = %{
  "chart" => "bar",
  "y" => [%{"field" => "nonexistent_column", "agg" => "sum"}]
}

case Lotus.validate_visualization_config(config, result) do
  :ok ->
    IO.puts("Config is valid")
  {:error, msg} ->
    IO.puts("Invalid config: #{msg}")
    # "y[0].field references unknown column 'nonexistent_column'"
end
```

The validation checks:
- Fields referenced in `x`, `y`, `series`, and `filters` exist in the result columns
- Numeric aggregations (`sum`, `avg`) are only applied to numeric columns

Note: This validation is optional. You can save any valid map as a visualization config.

### Updating and Deleting Visualizations

```elixir
# Update a visualization
{:ok, updated_viz} = Lotus.update_visualization(viz, %{
  name: "Updated Chart Name",
  position: 1
})

# Delete a visualization
{:ok, _} = Lotus.delete_visualization(viz)

# Visualizations are also cascade-deleted when their parent query is deleted
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
  statement: "SELECT COUNT(*) FROM users WHERE active = {{is_active}}",
  variables: [
    %{name: "is_active", type: :text, label: "Is Active", default: "true"}
  ],
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

Lotus supports smart variable substitution using `{{var}}` placeholders for safety and reusability:

```elixir
# Create a query with smart variables
{:ok, query} = Lotus.create_query(%{
  name: "Users by Status",
  statement: "SELECT id, name, email FROM users WHERE status = {{status}} AND created_at > {{created_date}}",
  variables: [
    %{name: "status", type: :text, label: "User Status", default: "active"},
    %{name: "created_date", type: :date, label: "Created After", default: "2024-01-01"}
  ]
})

# Run with the default variables
{:ok, result} = Lotus.run_query(query)

# Override variables at runtime
{:ok, result} = Lotus.run_query(query, vars: %{
  "status" => "pending",
  "created_date" => "2024-06-01"
})
```

### Variable Types and Widgets

Variables can be configured with different types and UI widgets to create better user interfaces:

```elixir
# Example with different variable types and widgets
attrs = %{
  name: "Active Users",
  statement: "SELECT * FROM users WHERE org_id = {{org_id}} AND created_at >= {{since}} AND status = {{status}}",
  variables: [
    # Number input with default
    %{name: "org_id", type: :number, label: "Organization ID", default: "1"},
    
    # Date input
    %{name: "since", type: :date, label: "Created Since"},
    
    # Static dropdown with predefined options
    %{
      name: "status", 
      type: :text, 
      widget: :select, 
      label: "Status",
      static_options: ["active", "inactive", "pending"]
    }
  ]
}

q = Lotus.Storage.Query.new(attrs) |> Repo.insert!()

# Use to_sql_params for parameterized queries
Lotus.Storage.Query.to_sql_params(q, %{"since" => "2024-01-01"})
# => {"SELECT * FROM users WHERE org_id = $1 AND created_at >= $2 AND status = $3", [1, ~D[2024-01-01], "active"]}
```

### Dynamic Dropdown Options

For select widgets, you can populate options dynamically using `options_query`:

```elixir
# Dynamic dropdown populated from database
%{
  name: "org_id",
  type: :number,
  widget: :select,
  label: "Organization",
  options_query: "SELECT id, name FROM orgs ORDER BY name"
}
```

The `options_query` should return two columns:
- First column: the value to be used in the query
- Second column: the label to display to users

### Variable Features

- **Safe substitution**: Variables are converted to database-specific placeholders with automatic type casting (`$1::integer` for PostgreSQL, `CAST(? AS SIGNED)` for MySQL, `?` for SQLite)
- **Structured variables**: Define variables with type, label, and default values for better UI integration  
- **Type support**: Supports text, number, integer, date, datetime, time, boolean, and json types with automatic database casting
- **Widget controls**: Specify input or select widgets for UI rendering
- **Static options**: Use `static_options` for predefined dropdown choices
- **Dynamic options**: Use `options_query` to populate dropdowns from database queries
- **Default values**: Provide fallback values in variable definitions
- **Runtime override**: Pass `vars:` option to override defaults
- **Multiple occurrences**: The same variable can appear multiple times and will be bound correctly
- **Type safety**: Variables are passed as parameters, preventing SQL injection

## Variable Type Casting

Lotus automatically generates type-specific SQL placeholders based on your variable types, ensuring proper data handling across different databases:

### PostgreSQL Type Casting
- `:integer` → `$1::integer`
- `:number` → `$1::numeric` 
- `:date` → `$1::date`
- `:datetime` → `$1::timestamp`
- `:time` → `$1::time`
- `:boolean` → `$1::boolean`
- `:json` → `$1::jsonb`
- `:text` (default) → `$1`

### MySQL Type Casting  
- `:integer` → `CAST(? AS SIGNED)`
- `:number` → `CAST(? AS DECIMAL)`
- `:date` → `CAST(? AS DATE)`
- `:datetime` → `CAST(? AS DATETIME)`
- `:time` → `CAST(? AS TIME)`
- `:boolean` → `CAST(? AS UNSIGNED)`
- `:json` → `CAST(? AS JSON)`
- `:text` (default) → `?`

### SQLite
SQLite uses untyped `?` placeholders for all variable types, as it handles type conversion automatically.

This type casting ensures that your data is properly handled by the database engine and can prevent runtime type errors.

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

## Using Lotus Web

If you prefer a visual interface or need to provide query access to non-technical users, consider setting up [Lotus Web](https://github.com/typhoonworks/lotus_web). It provides a beautiful web interface that mounts directly in your Phoenix application:

```elixir
# In your router
import Lotus.Web.Router

scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]
  
  lotus_dashboard "/lotus"
end
```

With Lotus Web, you get:
- A SQL editor with syntax highlighting
- Visual query management and organization
- Interactive schema exploration
- Real-time result visualization
- All without leaving your application

See the [installation guide](installation.md#lotus-web-setup) for detailed setup instructions.

## Next Steps

Now that you understand the basics, explore:

- [Configuration](configuration.md) - Learn about all available configuration options
