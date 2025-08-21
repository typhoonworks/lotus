# Installation

This guide walks you through setting up Lotus in your Elixir application.

## Requirements

- Elixir 1.16 or later
- OTP 25 or later
- An Ecto-based application with PostgreSQL or SQLite

## Step 1: Add Dependency

Add `lotus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 0.2.0"}
  ]
end
```

Run `mix deps.get` to fetch the dependency.

## Step 2: Configuration

Add Lotus configuration to your `config/config.exs`:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,        # Where Lotus stores queries
  data_repos: %{                 # Where queries execute
    "main" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo
  }
```

### Configuration Options

- `ecto_repo` (required): Repository where Lotus stores saved queries
- `data_repos` (required): Map of repositories where queries can be executed
- `unique_names`: Whether to enforce unique query names (default: `true`)
- `table_visibility`: Rules controlling which tables can be accessed (optional)

## Step 3: Run Migrations

Lotus needs to create tables in your database to store queries. Generate and run the migration:

```bash
mix ecto.gen.migration create_lotus_tables
```

Add the Lotus migration to your generated migration file:

```elixir
defmodule MyApp.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration

  def up do
    Lotus.Migrations.up()
  end

  def down do
    Lotus.Migrations.down()
  end
end
```

Run the migration:

```bash
mix ecto.migrate
```

## Step 4: Verify Installation

Test that Lotus is working correctly:

```elixir
# In iex -S mix
iex> Lotus.run_sql("SELECT 1 as test")
{:ok, %Lotus.QueryResult{rows: [[1]], columns: ["test"], num_rows: 1}}
```

## Database-Specific Setup

### PostgreSQL

Lotus works out of the box with PostgreSQL. Ensure your repository is configured with the `:postgrex` adapter:

```elixir
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_dev"
```

### SQLite

Lotus supports SQLite through the `ecto_sqlite3` adapter. Add the dependency to your `mix.exs`:

```elixir
{:ecto_sqlite3, "~> 0.11"}
```

Configure your SQLite repository:

```elixir
config :my_app, MyApp.SqliteRepo,
  adapter: Ecto.Adapters.SQLite3,
  database: Path.expand("../my_app.db", Path.dirname(__ENV__.file))
```

### Mixed Database Environments

You can use different database types for storage and data:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,          # PostgreSQL for Lotus storage
  data_repos: %{
    "postgres" => MyApp.Repo,     # PostgreSQL data
    "sqlite" => MyApp.SqliteRepo  # SQLite data
  }
```

### MySQL (Coming Soon)

MySQL support is planned for a future release.

## Troubleshooting

### Common Issues

**Configuration Error**: If you see `ArgumentError` with "Invalid :lotus config: required :ecto_repo option not found", ensure your repository is properly configured in your application config.

**Migration Issues**: If migrations fail, ensure your database is running and your repository configuration is correct.

**Permission Errors**: Lotus requires database access to create tables and execute queries. Ensure your database user has appropriate permissions.

## Next Steps

Now that Lotus is installed, check out the [Getting Started](getting-started.md) guide to create your first query.
