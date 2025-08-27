# Schema Introspection

Lotus provides powerful schema introspection capabilities for exploring database structure across multiple database types and schemas. This guide covers how to discover tables, inspect table schemas, and gather statistics about your data.

## Overview

The Schema module (`Lotus.Schema`) provides functions to:

- List tables across databases and schemas
- Inspect table structure and column information
- Get table statistics like row counts
- Work with multi-schema PostgreSQL databases
- Support PostgreSQL, MySQL, and SQLite databases

All Schema functions respect the configured table visibility rules, ensuring you only see tables you're allowed to access.

## Listing Tables

### Basic Usage

List all tables in your database:

```elixir
# List tables from the default public schema (PostgreSQL)
{:ok, tables} = Lotus.list_tables("postgres")
# Returns [{"public", "users"}, {"public", "posts"}, {"public", "comments"}]

# List tables from SQLite (no schema concept)
{:ok, tables} = Lotus.list_tables("sqlite")
# Returns ["products", "orders", "order_items"]
```

**Return Format:**
- **PostgreSQL**: Returns tuples of `{schema, table}` like `{"public", "users"}`
- **SQLite**: Returns simple strings like `"products"` (no schema concept)

### Working with PostgreSQL Schemas

PostgreSQL databases often use multiple schemas to organize tables. Lotus provides several ways to work with schemas:

#### Specific Schema

List tables from a specific schema:

```elixir
# List only tables in the reporting schema
{:ok, tables} = Lotus.list_tables("postgres", schema: "reporting")
# Returns [{"reporting", "customers"}, {"reporting", "revenue"}, {"reporting", "metrics"}]

# List from analytics schema
{:ok, tables} = Lotus.list_tables("postgres", schema: "analytics")
# Returns [{"analytics", "events"}, {"analytics", "sessions"}, {"analytics", "pageviews"}]
```

#### Multiple Schemas

List tables from multiple specific schemas:

```elixir
# List from both reporting and analytics schemas
{:ok, tables} = Lotus.list_tables("postgres", schemas: ["reporting", "analytics"])
# Returns [
#   {"analytics", "events"},
#   {"analytics", "sessions"},
#   {"reporting", "customers"},
#   {"reporting", "revenue"}
# ]
```

#### Using search_path

Use PostgreSQL's search_path concept to list tables from multiple schemas in priority order:

```elixir
# List tables using search_path (similar to PostgreSQL's native behavior)
{:ok, tables} = Lotus.list_tables("postgres", search_path: "reporting, analytics, public")
# Returns tables from all three schemas
```

### Including Views

By default, only tables are listed. To include views:

```elixir
# Include both tables and views
{:ok, relations} = Lotus.list_tables("postgres", 
  search_path: "reporting, public",
  include_views: true
)
# Returns both tables and views from the specified schemas
```

### Using Repository Modules

You can also use repository modules directly instead of repository names:

```elixir
# Use the repository module directly
{:ok, tables} = Lotus.list_tables(MyApp.ReportingRepo, schema: "reporting")

# Works with any configured repository
{:ok, tables} = Lotus.list_tables(MyApp.AnalyticsRepo)
```

## Getting Table Schema

Inspect the structure of a specific table to see columns, types, and constraints:

### Basic Table Schema

```elixir
# Get schema for a table
{:ok, schema} = Lotus.get_table_schema("postgres", "users")

# Each column entry contains:
# %{
#   name: "id",
#   type: "bigint",
#   nullable: false,
#   default: "nextval('users_id_seq'::regclass)",
#   primary_key: true
# }

# Inspect the columns
Enum.each(schema, fn col ->
  IO.puts("#{col.name}: #{col.type}#{if col.nullable, do: "", else: " NOT NULL"}")
end)
# id: bigint NOT NULL
# name: varchar(255) NOT NULL
# email: varchar(255) NOT NULL
# created_at: timestamp
# updated_at: timestamp
```

### Schema-Specific Tables

For PostgreSQL tables in non-public schemas:

```elixir
# Get schema for a table in the reporting schema
{:ok, schema} = Lotus.get_table_schema("postgres", "customers", schema: "reporting")

# Using search_path to find the table
{:ok, schema} = Lotus.get_table_schema("postgres", "revenue", 
  search_path: "reporting, analytics, public"
)
# Searches for 'revenue' table in each schema in order
```

### Column Information

The schema information includes detailed column metadata:

```elixir
{:ok, schema} = Lotus.get_table_schema("postgres", "products")

# Find specific column information
price_col = Enum.find(schema, &(&1.name == "price"))
# %{
#   name: "price",
#   type: "numeric(10,2)",
#   nullable: false,
#   default: "0.00",
#   primary_key: false
# }

# Check for primary keys
primary_keys = Enum.filter(schema, & &1.primary_key)
# [%{name: "id", type: "bigint", primary_key: true, ...}]

# Find nullable columns
nullable_cols = Enum.filter(schema, & &1.nullable)
```

### SQLite Schema

SQLite schema information has the same structure but different type representations:

```elixir
{:ok, schema} = Lotus.get_table_schema("sqlite", "products")

# SQLite types are simpler
# %{
#   name: "id",
#   type: "INTEGER",
#   nullable: true,  # SQLite represents PKs differently
#   default: nil,
#   primary_key: true
# }
```

## Getting Table Statistics

Get basic statistics about a table:

```elixir
# Get row count for a table
{:ok, stats} = Lotus.get_table_stats("postgres", "users")
# Returns %{row_count: 1234}

# For tables in specific schemas
{:ok, stats} = Lotus.get_table_stats("postgres", "customers", schema: "reporting")
# Returns %{row_count: 5678}

# Using search_path
{:ok, stats} = Lotus.get_table_stats("postgres", "events",
  search_path: "analytics, public"
)
```

## Listing Relations

The `list_relations` function returns tables with full schema information, useful for building UIs:

```elixir
# Get all relations (tables) with schema information
{:ok, relations} = Lotus.list_relations("postgres", search_path: "reporting, public")
# Always returns tuples: [{"reporting", "customers"}, {"public", "users"}, ...]

# For SQLite, includes nil schema
{:ok, relations} = Lotus.list_relations("sqlite")
# Returns [{nil, "products"}, {nil, "orders"}, ...]
```

This is particularly useful when you need consistent schema information across different database types.

## Multi-Tenant Scenarios

Schema introspection is particularly useful in multi-tenant applications:

### Schema-per-Tenant

```elixir
defmodule MyApp.TenantInspector do
  def list_tenant_tables(tenant_id) do
    schema_name = "tenant_#{tenant_id}"
    Lotus.list_tables("postgres", schema: schema_name)
  end

  def get_tenant_table_info(tenant_id, table_name) do
    schema_name = "tenant_#{tenant_id}"
    
    with {:ok, schema} <- Lotus.get_table_schema("postgres", table_name, 
                            schema: schema_name),
         {:ok, stats} <- Lotus.get_table_stats("postgres", table_name,
                           schema: schema_name) do
      {:ok, %{
        columns: schema,
        row_count: stats.row_count
      }}
    end
  end
end

# Usage
{:ok, tables} = MyApp.TenantInspector.list_tenant_tables(123)
{:ok, info} = MyApp.TenantInspector.get_tenant_table_info(123, "users")
```

### Shared Tables with Tenant-Specific Schemas

```elixir
# Core tables in public, tenant data in separate schemas
defmodule MyApp.SchemaExplorer do
  def explore_database do
    # Get shared tables
    {:ok, shared} = Lotus.list_tables("postgres", schema: "public")
    
    # Get tenant-specific tables
    {:ok, tenant_123} = Lotus.list_tables("postgres", schema: "tenant_123")
    {:ok, tenant_456} = Lotus.list_tables("postgres", schema: "tenant_456")
    
    %{
      shared_tables: shared,
      tenants: %{
        tenant_123: tenant_123,
        tenant_456: tenant_456
      }
    }
  end
end
```

## Building Admin Tools

Schema introspection is perfect for building administrative interfaces:

```elixir
defmodule MyApp.AdminDashboard do
  def database_overview(repo_name) do
    # Get all tables
    {:ok, tables} = Lotus.list_tables(repo_name, 
      search_path: "reporting, analytics, public",
      include_views: true
    )
    
    # Get stats for each table
    table_stats = Enum.map(tables, fn {schema, table} ->
      {:ok, stats} = Lotus.get_table_stats(repo_name, table, schema: schema)
      
      %{
        schema: schema,
        table: table,
        row_count: stats.row_count
      }
    end)
    
    # Sort by row count
    Enum.sort_by(table_stats, & &1.row_count, :desc)
  end
  
  def table_details(repo_name, schema_name, table_name) do
    with {:ok, columns} <- Lotus.get_table_schema(repo_name, table_name, 
                             schema: schema_name),
         {:ok, stats} <- Lotus.get_table_stats(repo_name, table_name,
                           schema: schema_name) do
      %{
        name: table_name,
        schema: schema_name,
        columns: columns,
        column_count: length(columns),
        row_count: stats.row_count,
        primary_keys: Enum.filter(columns, & &1.primary_key) |> Enum.map(& &1.name),
        nullable_columns: Enum.filter(columns, & &1.nullable) |> Enum.map(& &1.name)
      }
    end
  end
end

# Usage in a LiveView or controller
overview = MyApp.AdminDashboard.database_overview("postgres")
details = MyApp.AdminDashboard.table_details("postgres", "reporting", "customers")
```

## Error Handling

Schema functions return clear errors for common issues:

```elixir
# Table not found
{:error, msg} = Lotus.get_table_schema("postgres", "nonexistent")
# "Table 'nonexistent' not found in schemas: public"

# Table not in specified schema
{:error, msg} = Lotus.get_table_schema("postgres", "users", schema: "reporting")
# "Table 'users' not found in schemas: reporting"

# Table blocked by visibility rules
{:error, msg} = Lotus.get_table_schema("postgres", "api_keys")
# "Table 'public.api_keys' is not visible by Lotus policy"

# Invalid repository name
{:error, msg} = Lotus.list_tables("nonexistent_repo")
# "Data repo 'nonexistent_repo' not configured"
```

## Performance Considerations

Schema introspection queries are generally fast, but keep in mind:

1. **Caching**: Consider caching schema information if you're building UIs that frequently request it
2. **Large Schemas**: Databases with many schemas or tables may take longer to list
3. **Views**: Including views (`include_views: true`) may slow down queries in databases with complex views

```elixir
defmodule MyApp.SchemaCache do
  use GenServer
  
  def get_tables(repo_name, opts \\ []) do
    key = {repo_name, opts}
    
    case :ets.lookup(:schema_cache, key) do
      [{^key, tables, timestamp}] ->
        if timestamp > System.system_time(:second) - 300 do  # 5 minute cache
          {:ok, tables}
        else
          refresh_tables(repo_name, opts)
        end
      [] ->
        refresh_tables(repo_name, opts)
    end
  end
  
  defp refresh_tables(repo_name, opts) do
    case Lotus.list_tables(repo_name, opts) do
      {:ok, tables} = result ->
        :ets.insert(:schema_cache, {{repo_name, opts}, tables, System.system_time(:second)})
        result
      error ->
        error
    end
  end
end
```

## Integration with Query Building

Use schema introspection to help build queries:

```elixir
defmodule MyApp.QueryBuilder do
  def build_count_query(repo_name, schema_name, table_name) do
    # Verify table exists
    case Lotus.get_table_schema(repo_name, table_name, schema: schema_name) do
      {:ok, _schema} ->
        # Table exists, build query
        sql = if schema_name do
          "SELECT COUNT(*) as total FROM #{schema_name}.#{table_name}"
        else
          "SELECT COUNT(*) as total FROM #{table_name}"
        end
        
        Lotus.create_query(%{
          name: "Count #{schema_name}.#{table_name}",
          query: %{sql: sql},
          data_repo: repo_name,
          search_path: schema_name
        })
        
      {:error, reason} ->
        {:error, "Cannot create query: #{reason}"}
    end
  end
end
```

## Best Practices

### 1. Use Specific Schemas When Possible

```elixir
# Good - explicit schema
{:ok, tables} = Lotus.list_tables("postgres", schema: "reporting")

# Less specific - searches multiple schemas
{:ok, tables} = Lotus.list_tables("postgres", search_path: "reporting, analytics, public")
```

### 2. Handle Different Database Types

```elixir
def list_all_tables(repo_name) do
  case Lotus.list_tables(repo_name) do
    {:ok, tables} when is_list(tables) ->
      # Handle both tuple format (PostgreSQL) and string format (SQLite)
      normalized = Enum.map(tables, fn
        {schema, table} -> "#{schema}.#{table}"  # PostgreSQL
        table when is_binary(table) -> table      # SQLite
      end)
      {:ok, normalized}
    error ->
      error
  end
end
```

### 3. Check Table Existence Before Operations

```elixir
def safe_query_table(repo_name, table_name, schema_name \\ "public") do
  with {:ok, _schema} <- Lotus.get_table_schema(repo_name, table_name, schema: schema_name),
       {:ok, result} <- Lotus.run_sql("SELECT * FROM #{schema_name}.#{table_name} LIMIT 10", 
                          [], repo: repo_name) do
    {:ok, result}
  else
    {:error, reason} -> {:error, "Cannot query table: #{reason}"}
  end
end
```

### 4. Use Table Visibility for Security

Configure table visibility rules to ensure schema introspection only shows allowed tables:

```elixir
config :lotus,
  table_visibility: %{
    default: [
      # Bare strings block tables across ALL schemas
      deny: [
        "api_keys",         # Blocks api_keys in any schema
        "user_passwords",   # Blocks user_passwords in any schema
        "audit_logs"        # Blocks audit_logs in any schema
      ]
    ],
    reporting: [
      allow: [
        {"reporting", ~r/.*/},  # All reporting schema tables
        {"public", "users"},    # Specific public.users table
        "summaries"             # Allow 'summaries' table in any schema
      ]
    ]
  }
```

## Next Steps

- Learn about [Configuration](configuration.md) for table visibility rules
- Explore [Getting Started](getting-started.md) for query execution with schemas
- Check the [API Reference](https://hexdocs.pm/lotus) for detailed function documentation