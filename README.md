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

**The embeddable BI engine for Elixir apps — SQL editor, dashboards, visualizations, and AI-powered query generation that mount directly in your Phoenix app. No Metabase. No Redash. No extra infrastructure.**

[Try the live demo](https://lotus.typhoon.works/)

<!-- TODO: Replace with a 30-second demo GIF showing: mount in router → open browser → write SQL → see chart → save to dashboard -->

## Why Lotus?

Every app eventually needs analytics, reporting, or an internal SQL tool. The usual options — Metabase, Redash, Grafana — mean another service to deploy, another auth system to sync, another thing to keep running.

Lotus takes a different approach: it mounts inside your Phoenix app. Add the dependency, run a migration, add one line to your router, and you have a full BI interface — SQL editor, charts, dashboards — running on your existing infrastructure. Read-only by design, production-safe from day one.

We're running Lotus in production at [Accomplish](https://accomplish.dev).

## See It in Action

[Try the live demo](https://lotus.typhoon.works/) — a full Lotus Web instance with sample data.

**What you get out of the box:**
- Ask your database questions in plain English — AI-powered query generation with multi-turn conversations (bring your own OpenAI, Anthropic, or Gemini key)
- Web-based SQL editor with syntax highlighting and autocomplete
- Interactive schema explorer for browsing tables and columns
- 5 chart types (bar, line, area, scatter, pie) saved per query
- Dashboards with grid layouts, auto-refresh, and public sharing

Lotus Web is the companion UI package — see [lotus_web](https://github.com/typhoonworks/lotus_web).

## Quick Start

Get a fully working BI dashboard in your Phoenix app in under 5 minutes.

### 1. Add dependencies

```elixir
# mix.exs
def deps do
  [
    {:lotus, "~> 0.13.0"},
    {:lotus_web, "~> 0.12.0"}
  ]
end
```

### 2. Configure Lotus

```elixir
# config/config.exs
config :lotus,
  ecto_repo: MyApp.Repo,
  default_repo: "main",
  data_repos: %{
    "main" => MyApp.Repo
  }
```

### 3. Run the migration

```bash
mix ecto.gen.migration create_lotus_tables
```

```elixir
defmodule MyApp.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration

  def up, do: Lotus.Migrations.up()
  def down, do: Lotus.Migrations.down()
end
```

```bash
mix ecto.migrate
```

### 4. Mount in your router

```elixir
# lib/my_app_web/router.ex
import Lotus.Web.Router

scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  lotus_dashboard "/lotus"
end
```

### 5. Visit `/lotus` in your browser

That's it. You have a full BI dashboard running inside your Phoenix app.

For the complete setup guide (caching, multiple databases, visibility controls), see the [installation guide](guides/installation.md).

## Features

- **SQL editor** with syntax highlighting, autocomplete, and real-time execution
- **Query management** — save, organize, and reuse queries with descriptive names
- **Smart variables** — parameterize queries with `{{variable}}` syntax, configurable input widgets, and SQL-backed dropdown options
- **Visualizations** — 5 chart types (bar, line, area, scatter, pie) with renderer-agnostic config DSL
- **Dashboards** — combine queries into interactive views with 12-column grid layouts, auto-refresh, and public sharing via secure tokens
- **Multi-database support** — PostgreSQL, MySQL, and SQLite with per-query repo selection
- **Result caching** — TTL-based caching with ETS backend, cache profiles, and tag-based invalidation
- **CSV export** — download query results with streaming support for large datasets
- **Schema explorer** — browse tables, columns, and statistics interactively
- **AI query generation** — ask your database questions in plain English; schema-aware, multi-turn conversations using OpenAI, Anthropic, or Gemini (BYOK)
- **Read-only by design** — all queries run in read-only transactions with automatic timeout controls and session state management

## Production Ready

Lotus is built for production use from the ground up:

- **Read-only execution** — all queries run inside read-only transactions. No accidental writes.
- **Session state management** — connection pool state is automatically preserved and restored after each query, preventing pool pollution.
- **Automatic type casting** — query variables are cast to match column types (UUIDs, dates, numbers, booleans, enums) using schema metadata, with graceful fallbacks.
- **Timeout controls** — configurable per-query timeouts with sensible defaults.
- **Defense-in-depth** — preflight authorization, schema/table/column visibility controls, and built-in system table protection.

## Using Lotus as a Library

Lotus works great as a standalone library without the web UI. Use it to run queries, manage saved queries, and build analytics features programmatically.

### Configuration

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,
  default_repo: "main",
  data_repos: %{
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }

# Optional: Configure caching
config :lotus,
  cache: [
    adapter: Lotus.Cache.ETS,
    profiles: %{
      results: [ttl: 60_000],
      schema: [ttl: 3_600_000],
      options: [ttl: 300_000]
    }
  ]
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

### AI Query Generation

Ask your database questions in plain English. The AI assistant discovers your schema, respects visibility rules, and generates accurate, schema-qualified SQL. Supports multi-turn conversations for iterative refinement — no other embeddable BI tool does this.

```elixir
{:ok, result} = Lotus.AI.generate_query(
  prompt: "Show all customers with unpaid invoices",
  data_source: "my_repo"
)

result.sql
#=> "SELECT c.id, c.name FROM reporting.customers c ..."
```

Bring your own OpenAI, Anthropic, or Gemini API key. See the [AI query generation guide](guides/ai_query_generation.md) for setup and multi-turn conversation support.

## Configuration

See the [configuration guide](guides/configuration.md) for all options including:

- Data repository setup (single and multi-database)
- Schema, table, and column visibility controls
- Cache backends and TTL profiles
- AI provider configuration
- Query execution options (timeouts, search paths)

## How Lotus Compares

| | Lotus | Metabase | Redash | Blazer (Rails) | Livebook |
|---|---|---|---|---|---|
| **Deployment** | Mounts in your app | Separate service | Separate service | Mounts in your app | Separate service |
| **Extra infra** | None | Java + DB | Python + Redis + DB | None | None |
| **Auth** | Uses your app's auth | Separate auth system | Separate auth system | Uses your app's auth | Token-based |
| **Language** | Elixir | Java/Clojure | Python | Ruby | Elixir |
| **SQL editor** | Yes | Yes | Yes | Yes | Yes (in code cells) |
| **Dashboards** | Yes | Yes | Yes | No | No |
| **Charts** | 5 types | Many | Many | 3 types | Via libraries |
| **AI query gen** | Yes (BYOK) | No | No | No | No |
| **Read-only** | By design | Configurable | Configurable | Configurable | No |
| **Cost** | Free | Free/Paid | Free | Free | Free |

## Development Setup

### Prerequisites
- Elixir 1.17+ / OTP 25+
- PostgreSQL 14+, MySQL 8.0+, SQLite 3

### Setup

```bash
git clone https://github.com/typhoonworks/lotus.git
cd lotus
mix deps.get

# Optional: Start MySQL with Docker Compose
docker compose up -d mysql

mix ecto.create && mix ecto.migrate
```

### Running tests

```bash
mix test
```

## Contributing

See the [contribution guide](guides/contributing.md) for details on how to contribute to Lotus.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
