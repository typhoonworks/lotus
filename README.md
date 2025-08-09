# Lotus
<p>
  <a href="https://hex.pm/packages/lotus">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/lotus.svg">
  </a>
  <a href="https://hexdocs.pm/lotus">
    <img src="https://img.shields.io/badge/docs-hexdocs-blue" alt="HexDocs">
  </a>
  <a href="https://github.com/typhoonworks/lotus/actions">
    <img alt="CI Status" src="https://github.com/typhoonworks/lotus/workflows/ci/badge.svg">
  </a>
</p>

Lotus is a lightweight SQL query runner and storage library for Elixir applications with Ecto. It provides a safe, read-only environment for executing analytical queries while offering organized storage and management of saved queries.

>🚧 This library is in its infancy so you should treat all versions as early pre-release versions. We'll make the best effort to give heads up about breaking changes; however we can't guarantee backwards compatibility for every change.

## Current Features
- 🔐 **Read-only SQL execution** with built-in safety checks to prevent destructive operations
- 📦 **Query storage and management** - save, organize, and reuse SQL queries
- 🏗️ **Framework agnostic** - works with any Ecto-based application
- ⚡ **Configurable execution** with timeout controls and connection management
- 🎯 **Type-safe results** with structured query result handling

## What's planned?
- [ ] Query versioning and change tracking
- [ ] Query result caching mechanisms
- [ ] Query templates with parameter substitution
- [ ] Export functionality for query results (CSV, JSON)
- [ ] Multi-database support (MySQL, SQLite)

## Installation
Add `lotus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 0.1.0"}
  ]
end
```

Lotus requires Elixir 1.16 or later, and OTP 25 or later. It may work with earlier versions, but it wasn't tested against them.

Follow the [installation instructions](guides/installation.md) to set up Lotus in your application.

## Getting Started
Take a look at the [overview guide](guides/overview.md) for a quick introduction to Lotus.

## Configuration
View all the configuration options in the [configuration guide](guides/configuration.md).

## Basic Usage

### Configuration
Add to your config:

```elixir
config :lotus,
  repo: MyApp.Repo,
  primary_key_type: :id,    # or :binary_id
  foreign_key_type: :id     # or :binary_id
```

### Creating and Running Queries

```elixir
# Create and save a query
{:ok, query} = Lotus.create_query(%{
  name: "Active Users",
  query: %{sql: "SELECT * FROM users WHERE active = true"}
})

# Execute a saved query
{:ok, results} = Lotus.run_query(query)

# Execute SQL directly (read-only)
{:ok, results} = Lotus.run_sql("SELECT * FROM products WHERE price > $1", [100])
```

## Contributing
See the [contribution guide](guides/contributing.md) for details on how to contribute to Lotus.

## License
This project is licensed under the MIT License - see the LICENSE file for details.
