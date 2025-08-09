# Installation

This guide walks you through setting up Lotus in your Elixir application.

## Requirements

- Elixir 1.16 or later
- OTP 25 or later
- An Ecto-based application with PostgreSQL (MySQL and SQLite support coming soon)

## Step 1: Add Dependency

Add `lotus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 0.1.0"}
  ]
end
```

Run `mix deps.get` to fetch the dependency.

## Step 2: Configuration

Add Lotus configuration to your `config/config.exs`:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,
  primary_key_type: :id,    # or :binary_id
  foreign_key_type: :id     # or :binary_id
```

### Configuration Options

- `ecto_repo` (required): Your Ecto repository module
- `primary_key_type`: Primary key type for Lotus tables (`:id` or `:binary_id`)
- `foreign_key_type`: Foreign key type for Lotus tables (`:id` or `:binary_id`)
- `unique_names`: Whether to enforce unique query names (default: `true`)

## Step 3: Run Migrations

Lotus needs to create tables in your database to store queries. Generate and run the migration:

```bash
mix ecto.gen.migration create_lotus_tables
```

Add the Lotus migration to your generated migration file:

```elixir
defmodule MyApp.Repo.Migrations.CreateLotusTables do
  use Ecto.Migration
  use Lotus.Migrations

  def up do
    create_lotus_tables()
  end

  def down do
    drop_lotus_tables()
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

Lotus works out of the box with PostgreSQL. Ensure your repository is configured with the `:postgrex` adapter.

### MySQL (Coming Soon)

MySQL support is planned for a future release.

### SQLite (Coming Soon)

SQLite support is planned for a future release.

## Troubleshooting

### Common Issues

**Configuration Error**: If you see `ArgumentError` with "Invalid :lotus config: required :ecto_repo option not found", ensure your repository is properly configured in your application config.

**Migration Issues**: If migrations fail, ensure your database is running and your repository configuration is correct.

**Permission Errors**: Lotus requires database access to create tables and execute queries. Ensure your database user has appropriate permissions.

## Next Steps

Now that Lotus is installed, check out the [Getting Started](getting-started.md) guide to create your first query.