# Visibility Rules

Lotus provides a comprehensive visibility system that controls which schemas and tables are accessible through the API. This system operates on two levels with clear precedence rules to ensure security while maintaining flexibility.

## Overview

The visibility system uses a **two-level hierarchy**:

1. **Schema visibility** (higher precedence)
2. **Table visibility** (lower precedence)

**Key principle**: If a schema is denied, all tables within it are automatically blocked, regardless of table-level rules.

## Database-Specific Schema Behavior

Understanding how "schemas" work across different database systems is crucial for configuring visibility rules correctly:

### PostgreSQL
- **True namespaced schemas**: Multiple schemas exist within a single database
- **Examples**: `public`, `reporting`, `analytics`, `tenant_123`
- **System schemas**: `pg_catalog`, `information_schema`, `pg_toast`, `pg_temp_*`
- **Qualified names**: `reporting.customers`, `public.users`

### MySQL
- **Schemas = Databases**: In MySQL, "schema" and "database" are synonymous
- **Examples**: `lotus_production`, `analytics_db`, `warehouse`
- **System schemas**: `mysql`, `information_schema`, `performance_schema`, `sys`
- **Behavior**: When you connect to MySQL, you can access tables across different databases/schemas
- **Qualified names**: `analytics_db.customers`, `warehouse.sales`

### SQLite
- **No schema support**: SQLite is schema-less
- **Schema visibility**: Not applicable (always empty list)
- **Tables**: Exist at the database level without namespace prefixes

## Configuration

Configure visibility rules in your application config:

```elixir
config :lotus,
  # Schema-level visibility (higher precedence)
  schema_visibility: %{
    default: [
      deny: ["restricted_schema", ~r/^temp_/],
      allow: :all  # or specific schemas
    ],
    postgres: [
      # Only allow public and tenant schemas
      allow: ["public", ~r/^tenant_\d+$/],
      deny: ["legacy_schema"]
    ],
    mysql: [
      # In MySQL, these are database names
      allow: ["lotus_production", "analytics_warehouse"],
      deny: ["staging_db", "backup_db"]
    ]
  },

  # Table-level visibility (lower precedence)
  table_visibility: %{
    default: [
      deny: ["user_passwords", "api_keys", ~r/^audit_/],
      allow: []  # empty = allow all (except denied)
    ],
    postgres: [
      # Data warehouse example
      allow: [
        {"public", ~r/^dim_/},      # Dimension tables
        {"public", ~r/^fact_/},     # Fact tables
        {"analytics", ~r/.*/}       # All analytics tables
      ],
      deny: [
        {"public", ~r/^staging_/},  # Block staging tables
        {"public", ~r/_temp$/}      # Block temp tables
      ]
    ]
  }
```

## Rule Syntax

### Schema Rules

Schema rules use simpler patterns since they only match schema names:

- `"exact_name"` - Matches exact schema name
- `~r/pattern/` - Regex pattern for dynamic matching
- `:all` - Special value for allow rules (allows all schemas)

**Examples**:
```elixir
allow: ["public", "reporting", ~r/^tenant_\w+$/]
deny: ["restricted", ~r/^temp_/]
```

### Table Rules

Table rules support multiple formats for maximum flexibility:

- `{"schema", "table"}` - Exact schema.table match
- `{"schema", ~r/pattern/}` - Regex table pattern in specific schema
- `{~r/schema_pattern/, "table"}` - Table in schemas matching pattern
- `"table"` - Table name in any schema (global rule)

**Examples**:
```elixir
allow: [
  {"public", "users"},           # Specific table
  {"reporting", ~r/^daily_/},    # Tables starting with "daily_" in reporting
  {~r/^tenant_/, "customers"},   # customers table in any tenant schema
  "products"                     # products table in any schema
]
```

## Precedence and Evaluation

### 1. Schema Gating (First)
```elixir
if not allowed_schema?(schema) do
  deny  # Schema denied → everything in it blocked
else
  # Schema allowed → proceed to table rules
end
```

### 2. Deny Always Wins (Second)
```elixir
if deny_rule_matches?(schema, table) do
  deny  # Any deny rule blocks access
else
  # Check allow posture
end
```

### 3. Schema-Scoped Allow Posture (Third)
For each schema, compute its "allow posture":

- **Has allow posture**: Allow rules exist that could apply to this schema
- **No allow posture**: No allow rules target this schema

```elixir
# Rules: allow: [{"restricted", "allowed_table"}]

# For "restricted" schema:
allow_posture? = true   # Has rule targeting "restricted"
# → Default-deny: only "allowed_table" allowed

# For "public" schema:
allow_posture? = false  # No rules targeting "public"
# → Default-allow: all tables allowed (unless denied)
```

## Practical Examples

### Multi-Tenant SaaS Application

```elixir
config :lotus,
  schema_visibility: %{
    postgres: [
      # Only allow public and tenant schemas
      allow: ["public", ~r/^tenant_\d+$/],
      deny: ["admin_schema", "system_logs"]
    ]
  },
  table_visibility: %{
    postgres: [
      allow: [
        {"public", ~r/^shared_/},        # Shared lookup tables
        {~r/^tenant_/, "users"},         # User table in each tenant
        {~r/^tenant_/, "orders"},        # Order table in each tenant
        {~r/^tenant_/, "products"}       # Product table in each tenant
      ],
      deny: [
        {~r/^tenant_/, "internal_logs"}, # Hide logs from all tenants
        "api_keys"                       # Hide API keys globally
      ]
    ]
  }
```

**Result**:
- ✅ `tenant_123.users` → Allowed
- ✅ `public.shared_categories` → Allowed
- ❌ `tenant_123.internal_logs` → Denied (table rule)
- ❌ `admin_schema.anything` → Denied (schema rule)

### Data Warehouse

```elixir
config :lotus,
  schema_visibility: %{
    postgres: [
      allow: ["public", "warehouse", "analytics"],
      deny: ["staging", "etl_temp"]
    ]
  },
  table_visibility: %{
    postgres: [
      allow: [
        {"public", ~r/^dim_/},         # Dimension tables
        {"public", ~r/^fact_/},        # Fact tables
        {"warehouse", ~r/.*/},         # All warehouse tables
        {"analytics", ~r/^report_/}    # Only report tables in analytics
      ],
      deny: [
        {"public", ~r/^raw_/},         # Hide raw data tables
        {"warehouse", ~r/_backup$/}    # Hide backup tables
      ]
    ]
  }
```

### MySQL Multi-Database Setup

```elixir
config :lotus,
  schema_visibility: %{
    mysql: [
      # Remember: schemas = databases in MySQL
      allow: ["lotus_production", "analytics_warehouse", "reporting_db"],
      deny: ["staging_db", "backup_db", "temp_imports"]
    ]
  },
  table_visibility: %{
    mysql: [
      allow: [
        {"lotus_production", ~r/^public_/},    # Only public tables from main DB
        {"analytics_warehouse", ~r/.*/},       # All analytics tables
        {"reporting_db", ~r/^report_/}         # Only reports from reporting DB
      ],
      deny: [
        "user_passwords",                      # Hide globally
        {"lotus_production", ~r/^internal_/}   # Hide internal tables
      ]
    ]
  }
```

## Testing Visibility Rules

You can test your visibility configuration using the programmatic API:

```elixir
# Test schema visibility
{:ok, schemas} = Lotus.list_schemas("postgres")
# Returns only visible schemas

# Test table visibility
{:ok, tables} = Lotus.list_tables("postgres", schema: "public")
# Returns only visible tables in public schema

# Direct visibility check
Lotus.Visibility.allowed_schema?("postgres", "restricted")
# Returns true/false

Lotus.Visibility.allowed_relation?("postgres", {"public", "users"})
# Returns true/false
```

## Error Handling

When schema visibility blocks access, you'll receive clear error messages:

```elixir
# Trying to list tables in denied schema
{:error, "Schema(s) not visible: pg_catalog, restricted"} =
  Lotus.list_tables("postgres", schemas: ["public", "pg_catalog", "restricted"])

# Validation helper
{:error, :schema_not_visible, denied: ["pg_catalog"]} =
  Lotus.Visibility.validate_schemas(["public", "pg_catalog"], "postgres")
```

## Built-in Security

Lotus automatically denies system schemas to prevent accidental exposure:

### PostgreSQL Built-ins
- `pg_catalog` - System catalog
- `information_schema` - SQL standard metadata
- `pg_toast` - TOAST storage
- `~r/^pg_temp/` - Temporary schemas
- `~r/^pg_toast/` - Additional TOAST schemas

### MySQL Built-ins
- `mysql` - MySQL system database
- `information_schema` - SQL standard metadata
- `performance_schema` - Performance monitoring
- `sys` - Diagnostic information

### All Databases
- Migration tables (e.g., `schema_migrations`)
- Lotus internal tables (e.g., `lotus_queries`)

These built-in denies always apply, even if your custom rules would allow them. This ensures security by default.

## Migration from Table-Only Rules

If you're upgrading from table-only visibility rules:

1. **Review existing rules**: Identify any schema-specific patterns
2. **Extract schema rules**: Move schema-level restrictions to `schema_visibility`
3. **Test thoroughly**: Schema rules take precedence and can block more than expected
4. **Use validation**: Test your configuration with `Lotus.Visibility.validate_schemas/2`

## Best Practices

1. **Start restrictive**: Use allow lists for sensitive environments
2. **Layer security**: Use schema rules for broad restrictions, table rules for fine-tuning
3. **Test configurations**: Use the programmatic API to verify your rules work as expected
4. **Document your rules**: Complex visibility configurations should be documented for your team
5. **Consider performance**: Schema-level filtering is more efficient than table-level
6. **MySQL considerations**: Remember that schemas = databases in MySQL
7. **Regex careful**: Test regex patterns thoroughly to avoid unintended matches

## Common Patterns

### Development vs Production

```elixir
# Development - more permissive
config :lotus,
  schema_visibility: %{
    default: [allow: :all, deny: ["dangerous_schema"]]
  }

# Production - restrictive allowlist
config :lotus,
  schema_visibility: %{
    default: [
      allow: ["public", "reporting"],
      deny: []  # not needed with restrictive allow
    ]
  }
```

### Dynamic tenant schemas

```elixir
config :lotus,
  schema_visibility: %{
    postgres: [
      allow: ["public", ~r/^tenant_[a-f0-9]{8}$/],  # UUID-based tenants
      deny: []
    ]
  }
```
