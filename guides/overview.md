# Overview

Lotus is a lightweight library that provides safe, read-only SQL query execution and management for Elixir applications using Ecto. It's designed to help you organize and execute analytical queries while maintaining strict safety controls.

## Why Lotus?

Modern applications often need to run complex analytical queries for reporting, business intelligence, or data exploration. However, executing arbitrary SQL in production environments comes with significant risks:

- **Security concerns**: Unrestricted SQL access can lead to data breaches or accidental damage
- **Performance issues**: Poorly written queries can impact application performance
- **Organization challenges**: Ad-hoc queries scattered across codebases are hard to maintain
- **Reusability problems**: Useful queries get lost or duplicated

Lotus addresses these challenges by providing:

## Key Benefits

### 🔐 Safety First
- **Read-only execution**: Built-in protections prevent destructive operations
- **Statement validation**: Queries are checked before execution
- **Database-level guards**: PostgreSQL (`transaction_read_only`), MySQL (`transaction_read_only`), and SQLite 3.8.0+ (`PRAGMA query_only`)
- **Session state preservation**: Automatically snapshots and restores original database session settings to prevent connection pool pollution
- **Table visibility controls**: Configurable rules block access to sensitive tables
- **Multi-layered security**: Defense-in-depth with preflight authorization
- **Timeout controls**: Configurable timeouts prevent runaway queries

### 📦 Organized Storage
- **Persistent queries**: Save and organize your SQL queries
- **Version control friendly**: Queries are stored in your database, not scattered in code
- **Easy retrieval**: Simple API to find and execute saved queries

### 🏗️ Framework Agnostic
- **Ecto integration**: Works with any Ecto-based application
- **Multi-database support**: Supports PostgreSQL, MySQL, and SQLite simultaneously
- **Flexible architecture**: Separate storage and execution repositories
- **Minimal dependencies**: Lightweight with few external requirements

### ⚡ Developer Friendly
- **Simple API**: Intuitive functions for creating and running queries
- **Type safety**: Structured results with proper error handling
- **Configuration**: Flexible setup to match your application's needs
- **Schema introspection**: Discover tables, inspect schemas, and gather statistics

## Core Concepts

### Queries
A query in Lotus is a saved SQL statement with metadata like name and creation time. Queries are stored in your database and can be executed repeatedly.

### Execution
All SQL execution happens through Lotus's runner, which enforces read-only restrictions and provides consistent error handling and timeout management.

### Results
Query results are returned in a structured format (`Result`) that includes the data and column information.

### Visualizations
Visualizations are saved chart configurations attached to queries. Lotus stores the config as an opaque map, giving consumers full flexibility over the structure. Frontend applications like Lotus Web can transform this config into concrete chart specs (Vega-Lite, Recharts, etc.).

Before saving, you can use `Lotus.validate_visualization_config/2` to verify that field references in your config exist in the query results and that numeric aggregations apply to numeric columns. This validation is optional and does not enforce any particular config structure.

### Schema Introspection
Lotus provides comprehensive schema discovery tools to explore database structure, list tables across schemas, inspect column definitions, and gather table statistics.

## Use Cases

Lotus is perfect for:

- **Reporting dashboards**: Execute saved queries to generate reports
- **Data exploration**: Safely allow analysts to run custom queries
- **Business intelligence**: Organize and execute analytical queries
- **Metrics collection**: Store and run queries for application metrics
- **Data exports**: Generate data extracts with saved, tested queries
- **Database administration**: Explore table structures and gather statistics
- **Multi-tenant applications**: Manage schema-per-tenant architectures

## Lotus Web UI

For teams that need a visual interface, [Lotus Web](https://github.com/typhoonworks/lotus_web) provides a Phoenix LiveView-powered dashboard that you can mount directly in your application. It's a lightweight alternative to complex BI tools like Metabase or Grafana, offering:

- **Web-based SQL editor** with syntax highlighting
- **Interactive query management** and organization
- **Schema exploration** to browse tables and columns
- **Real-time query execution** with clean result visualization
- **Multi-database support** to query different repositories
- **Zero additional infrastructure** - runs inside your Phoenix app

## What's Next?

Continue with the [Installation Guide](installation.md) to set up Lotus in your application, then check out [Getting Started](getting-started.md) for your first queries.
