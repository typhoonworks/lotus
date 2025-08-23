# Lotus

![Lotus](https://raw.githubusercontent.com/typhoonworks/lotus/main/media/banner.png)

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
- 🔐 **Enhanced security** with read-only execution and table visibility controls
- 📦 **Query storage and management** - save, organize, and reuse SQL queries
- 🏗️ **Multi-database support** - PostgreSQL and SQLite with flexible repository architecture
- ⚡ **Configurable execution** with timeout controls and connection management
- 🎯 **Type-safe results** with structured query result handling
- 🛡️ **Defense-in-depth** with preflight authorization and built-in system table protection

## What's planned?
- [ ] Query versioning and change tracking
- [ ] Query result caching mechanisms
- [ ] Export functionality for query results (CSV, JSON)
- [ ] MySQL support
- [x] Multi-database support (PostgreSQL, SQLite)
- [x] Table visibility and access controls
- [x] Query templates with parameter substitution using `{var}` placeholders

## Installation
Add `lotus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 0.2.0"}
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
  ecto_repo: MyApp.Repo,  # Repo where Lotus stores saved queries
  data_repos: %{           # Repos where queries run against actual data
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

### Creating and Running Queries

```elixir
# Create and save a query
{:ok, query} = Lotus.create_query(%{
  name: "Active Users",
  statement: "SELECT * FROM users WHERE active = true"
})

# Execute a saved query
{:ok, results} = Lotus.run_query(query)

# Execute SQL directly (read-only)
{:ok, results} = Lotus.run_sql("SELECT * FROM products WHERE price > $1", [100])

# Execute against a specific data repository
{:ok, results} = Lotus.run_sql("SELECT COUNT(*) FROM events", [], repo: "analytics")
```

## Development Setup

### Prerequisites
- PostgreSQL (tested with version 14+)
- SQLite 3
- Elixir 1.16+
- OTP 25+

### Setting up the development environment

1. Clone the repository and install dependencies:
```bash
git clone https://github.com/typhoonworks/lotus.git
cd lotus
mix deps.get
```

2. Set up the development databases:
```bash
mix ecto.create
mix ecto.migrate
```

This creates:
- PostgreSQL database (`lotus_dev`) with both Lotus tables and test data tables
- SQLite database (`lotus_dev.db`) with e-commerce sample data

### Running tests

```bash
# Run all tests
mix test

# Run specific test files
mix test test/lotus_test.exs

# Run with coverage
mix test --cover
```

The test suite uses separate databases:
- PostgreSQL: `lotus_test` (with partitioning for parallel tests)
- SQLite: `lotus_sqlite_test.db`

## Contributing
See the [contribution guide](guides/contributing.md) for details on how to contribute to Lotus.

## License
This project is licensed under the MIT License - see the LICENSE file for details.
