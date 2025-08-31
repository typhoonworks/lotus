# Advanced Variables

This guide covers advanced variable usage patterns in Lotus queries, including how the SQL transformer handles database-specific syntax compatibility and advanced patterns for cross-database applications.

## SQL Transformer Overview

Lotus includes an automatic SQL transformer that ensures your queries work correctly across different database systems. When you execute a query, Lotus automatically transforms the SQL to match the target database's syntax requirements, particularly around variable placeholders and database-specific functions.

The transformer handles three main areas:
- **Quoted Variable Stripping**: Removes unnecessary quotes around variable placeholders
- **Wildcard Pattern Transformation**: Converts quoted wildcard patterns to database-specific concatenation
- **Interval Query Transformation**: Transforms PostgreSQL interval syntax for compatibility

## Quoted Variable Handling

The transformer automatically handles quoted variables to ensure proper parameter binding across databases.

### Safe Quote Stripping

Variables wrapped in single quotes are automatically stripped when they represent simple scalar values:

```elixir
# Original query
query = %Query{
  statement: "SELECT * FROM users WHERE email = '{{email}}'",
  variables: [%{name: "email", type: :text, default: nil}]
}

# Lotus transforms this to:
# "SELECT * FROM users WHERE email = {{email}}"
# Which becomes: "SELECT * FROM users WHERE email = $1" (PostgreSQL)
```

This works across all supported databases:

**PostgreSQL:**
```sql
-- Original: WHERE name = '{{name}}'
-- Becomes:  WHERE name = $1
```

**MySQL:**
```sql
-- Original: WHERE name = '{{name}}'
-- Becomes:  WHERE name = ?
```

**SQLite:**
```sql
-- Original: WHERE name = '{{name}}'
-- Becomes:  WHERE name = ?
```

### Type Casting Support

Quote stripping works with PostgreSQL type casting:

```elixir
query = %Query{
  statement: "SELECT * FROM users WHERE id = '{{user_id}}'::int",
  variables: [%{name: "user_id", type: :number, default: nil}]
}

# Transforms to: "SELECT * FROM users WHERE id = {{user_id}}::int"
# Final result: "SELECT * FROM users WHERE id = $1::int"
```

### Protected Wildcard Patterns

Wildcard patterns are **NOT** stripped because they need special handling:

```elixir
query = %Query{
  statement: "SELECT * FROM users WHERE name LIKE '%{{search}}%'",
  variables: [%{name: "search", type: :text, default: nil}]
}

# The '%{{search}}%' pattern is preserved and transformed differently
# See Wildcard Pattern Transformation section below
```

## Wildcard Pattern Transformation

One of the most powerful features of the SQL transformer is its ability to handle wildcard search patterns correctly across different database systems.

### The Problem

When you write a query like this:

```sql
SELECT * FROM users WHERE name LIKE '%{{search}}%'
```

The quotes around `%{{search}}%` create a problem: the variable placeholder ends up inside a string literal, which breaks parameter binding and prevents the database from properly executing the query.

### The Solution

Lotus automatically transforms these patterns into database-specific concatenation:

#### PostgreSQL (|| operator)

```elixir
# Original query
statement: "SELECT * FROM users WHERE name LIKE '%{{search}}%'"

# Transforms to:
# "SELECT * FROM users WHERE name LIKE '%' || {{search}} || '%'"

# Final result:
# "SELECT * FROM users WHERE name LIKE '%' || $1 || '%'"
```

#### MySQL (CONCAT function)

```elixir
# Original query
statement: "SELECT * FROM users WHERE name LIKE '%{{search}}%'"

# Transforms to:
# "SELECT * FROM users WHERE name LIKE CONCAT('%', {{search}}, '%')"

# Final result:
# "SELECT * FROM users WHERE name LIKE CONCAT('%', ?, '%')"
```

#### SQLite (|| operator)

```elixir
# Original query
statement: "SELECT * FROM users WHERE name LIKE '%{{search}}%'"

# Transforms to:
# "SELECT * FROM users WHERE name LIKE '%' || {{search}} || '%'"

# Final result:
# "SELECT * FROM users WHERE name LIKE '%' || ? || '%'"
```

### Supported Wildcard Patterns

The transformer recognizes and handles these wildcard patterns:

#### Both-Sided Wildcards: `'%{{var}}%'`
```elixir
# Original
"WHERE title LIKE '%{{search}}%'"

# PostgreSQL/SQLite: "WHERE title LIKE '%' || {{search}} || '%'"
# MySQL: "WHERE title LIKE CONCAT('%', {{search}}, '%')"
```

#### Left Wildcard: `'%{{var}}'`
```elixir
# Original
"WHERE email LIKE '%{{domain}}'"

# PostgreSQL/SQLite: "WHERE email LIKE '%' || {{domain}}"
# MySQL: "WHERE email LIKE CONCAT('%', {{domain}})"
```

#### Right Wildcard: `'{{var}}%'`
```elixir
# Original
"WHERE name LIKE '{{prefix}}%'"

# PostgreSQL/SQLite: "WHERE name LIKE {{prefix}} || '%'"
# MySQL: "WHERE name LIKE CONCAT({{prefix}}, '%')"
```

### Practical Examples

Here are real-world examples of wildcard pattern usage:

#### Flexible Search Query

```elixir
{:ok, search_query} = Lotus.create_query(%{
  name: "User Search",
  statement: """
  SELECT id, name, email
  FROM users
  WHERE
    (name LIKE '%{{search}}%' OR email LIKE '%{{search}}%')
    AND status = {{status}}
  ORDER BY name
  """,
  variables: [
    %{name: "search", type: :text, label: "Search Term", default: ""},
    %{name: "status", type: :text, label: "Status", default: "active"}
  ]
})

# Works identically on PostgreSQL, MySQL, and SQLite
{:ok, result} = Lotus.run_query(search_query, vars: %{
  "search" => "john",
  "status" => "active"
})
```

#### Domain-Based Filtering

```elixir
{:ok, domain_query} = Lotus.create_query(%{
  name: "Users by Email Domain",
  statement: """
  SELECT COUNT(*) as user_count
  FROM users
  WHERE email LIKE '%{{domain}}'
    AND created_at >= {{since}}
  """,
  variables: [
    %{name: "domain", type: :text, label: "Email Domain", default: "@company.com"},
    %{name: "since", type: :date, label: "Since Date", default: "2024-01-01"}
  ]
})

# Execute against different databases
{:ok, pg_result} = Lotus.run_query(domain_query, repo: "postgres")
{:ok, mysql_result} = Lotus.run_query(domain_query, repo: "mysql")
```

## PostgreSQL Interval Query Transformation

For PostgreSQL databases, Lotus provides sophisticated transformation of INTERVAL syntax to make your time-based queries more flexible and variable-friendly.

### Standard PostgreSQL Interval Limitations

PostgreSQL's INTERVAL syntax can be restrictive when you want to use variables:

```sql
-- This works fine
SELECT * FROM posts WHERE created_at > NOW() - INTERVAL '7 days'

-- But this doesn't work with variables in standard SQL
SELECT * FROM posts WHERE created_at > NOW() - INTERVAL '{{days}} days'
```

### Lotus Interval Transformations

Lotus transforms various interval patterns to work seamlessly with variables:

#### Pattern 1: `INTERVAL '{{var}} unit'`

```elixir
# Original query
statement: """
SELECT title FROM posts
WHERE published_at >= NOW() - INTERVAL '{{days}} days'
"""

# Transforms to:
# "SELECT title FROM posts WHERE published_at >= NOW() - make_interval(days => ({{days}})::integer)"
```

#### Pattern 2: `INTERVAL '{{num}} {{unit}}'`

```elixir
# Original query
statement: """
SELECT COUNT(*) FROM events
WHERE created_at >= NOW() - INTERVAL '{{amount}} {{period}}'
"""

# Transforms to:
# "SELECT COUNT(*) FROM events WHERE created_at >= NOW() - ((CAST({{amount}} AS text) || ' ' || {{period}})::interval)"
```

#### Pattern 3: `INTERVAL {{full_interval}}`

```elixir
# Original query
statement: """
SELECT * FROM logs
WHERE timestamp >= NOW() - INTERVAL {{time_range}}
"""

# Transforms to:
# "SELECT * FROM logs WHERE timestamp >= NOW() - ({{time_range}}::text)::interval"
```

#### Pattern 4: `INTERVAL '7 {{unit}}'` (Fixed Number, Variable Unit)

```elixir
# Original query
statement: """
SELECT COUNT(*) FROM sessions
WHERE last_activity >= NOW() - INTERVAL '7 {{unit}}'
"""

# Transforms to:
# "SELECT COUNT(*) FROM sessions WHERE last_activity >= NOW() - (( '7 ' || {{unit}} )::interval)"
```

### Practical PostgreSQL Interval Examples

#### Time-Range Analytics Query

```elixir
{:ok, analytics_query} = Lotus.create_query(%{
  name: "Activity Analytics",
  statement: """
  SELECT
    DATE_TRUNC('day', created_at) as day,
    COUNT(*) as events,
    COUNT(DISTINCT user_id) as unique_users
  FROM user_events
  WHERE created_at >= NOW() - INTERVAL '{{days}} days'
  GROUP BY 1
  ORDER BY 1 DESC
  """,
  variables: [
    %{name: "days", type: :number, label: "Days Back", default: "30"}
  ],
  data_repo: "postgres"
})

# Execute with different time ranges
{:ok, week_data} = Lotus.run_query(analytics_query, vars: %{"days" => 7})
{:ok, month_data} = Lotus.run_query(analytics_query, vars: %{"days" => 30})
```

#### Flexible Retention Query

```elixir
{:ok, retention_query} = Lotus.create_query(%{
  name: "User Retention Analysis",
  statement: """
  SELECT
    retention_period,
    COUNT(DISTINCT user_id) as active_users,
    ROUND(100.0 * COUNT(DISTINCT user_id) / (
      SELECT COUNT(*) FROM users
      WHERE created_at <= NOW() - INTERVAL '{{period}} {{unit}}'
    ), 2) as retention_rate
  FROM (
    SELECT
      user_id,
      '{{period}} {{unit}}' as retention_period
    FROM user_activity
    WHERE last_seen >= NOW() - INTERVAL '{{period}} {{unit}}'
  ) retention_data
  GROUP BY retention_period
  """,
  variables: [
    %{name: "period", type: :number, label: "Time Period", default: "3"},
    %{name: "unit", type: :text, label: "Time Unit", default: "months",
      widget: :select, static_options: ["days", "weeks", "months", "years"]}
  ],
  data_repo: "postgres"
})
```

#### Dynamic Report with Full Interval String

```elixir
{:ok, report_query} = Lotus.create_query(%{
  name: "Flexible Time Report",
  statement: """
  SELECT
    '{{interval}}' as time_range,
    COUNT(*) as total_records,
    AVG(amount) as avg_amount,
    SUM(amount) as total_amount
  FROM transactions
  WHERE created_at >= NOW() - INTERVAL {{interval}}
  """,
  variables: [
    %{name: "interval", type: :text, label: "Time Range", default: "1 month",
      widget: :select, static_options: [
        "1 day", "3 days", "1 week", "2 weeks",
        "1 month", "3 months", "6 months", "1 year"
      ]}
  ],
  data_repo: "postgres"
})
```

### Non-PostgreSQL Behavior

For MySQL and SQLite databases, interval transformations are safely ignored since these databases don't support PostgreSQL's INTERVAL syntax:

```elixir
# PostgreSQL query with intervals
{:ok, pg_query} = Lotus.create_query(%{
  name: "PostgreSQL Time Query",
  statement: "SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '{{days}} days'",
  variables: [%{name: "days", type: :number, default: "7"}],
  data_repo: "postgres"
})

# MySQL equivalent (no transformation needed)
{:ok, mysql_query} = Lotus.create_query(%{
  name: "MySQL Time Query",
  statement: "SELECT * FROM events WHERE created_at >= NOW() - INTERVAL {{days}} DAY",
  variables: [%{name: "days", type: :number, default: "7"}],
  data_repo: "mysql"
})

# SQLite equivalent (no transformation needed)
{:ok, sqlite_query} = Lotus.create_query(%{
  name: "SQLite Time Query",
  statement: "SELECT * FROM events WHERE created_at >= datetime('now', '-' || {{days}} || ' days')",
  variables: [%{name: "days", type: :number, default: "7"}],
  data_repo: "sqlite"
})
```
