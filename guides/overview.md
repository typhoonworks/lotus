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
- **Timeout controls**: Configurable timeouts prevent runaway queries

### 📦 Organized Storage
- **Persistent queries**: Save and organize your SQL queries
- **Version control friendly**: Queries are stored in your database, not scattered in code
- **Easy retrieval**: Simple API to find and execute saved queries

### 🏗️ Framework Agnostic
- **Ecto integration**: Works with any Ecto-based application
- **Database agnostic**: Supports PostgreSQL (with MySQL and SQLite planned)
- **Minimal dependencies**: Lightweight with few external requirements

### ⚡ Developer Friendly
- **Simple API**: Intuitive functions for creating and running queries
- **Type safety**: Structured results with proper error handling
- **Configuration**: Flexible setup to match your application's needs

## Core Concepts

### Queries
A query in Lotus is a saved SQL statement with metadata like name and creation time. Queries are stored in your database and can be executed repeatedly.

### Execution
All SQL execution happens through Lotus's runner, which enforces read-only restrictions and provides consistent error handling and timeout management.

### Results
Query results are returned in a structured format (`QueryResult`) that includes the data and column information.

## Use Cases

Lotus is perfect for:

- **Reporting dashboards**: Execute saved queries to generate reports
- **Data exploration**: Safely allow analysts to run custom queries
- **Business intelligence**: Organize and execute analytical queries
- **Metrics collection**: Store and run queries for application metrics
- **Data exports**: Generate data extracts with saved, tested queries

## What's Next?

Continue with the [Installation Guide](installation.md) to set up Lotus in your application, then check out [Getting Started](getting-started.md) for your first queries.
