# Configuration

This guide covers all configuration options available in Lotus and how to customize the library for your specific needs.

## Basic Configuration

Lotus configuration is typically placed in your `config/config.exs` file:

```elixir
config :lotus,
  ecto_repo: MyApp.Repo,
  primary_key_type: :id,
  foreign_key_type: :id,
  unique_names: true
```

## Configuration Options

### Required Options

#### `ecto_repo` (required)

Specifies the Ecto repository that Lotus will use for database operations.

```elixir
config :lotus,
  ecto_repo: MyApp.Repo
```

**Type**: `module()`

### Schema Options

#### `primary_key_type`

Defines the primary key type for Lotus tables.

```elixir
config :lotus,
  primary_key_type: :id        # Integer primary keys
  # or
  primary_key_type: :binary_id # Binary ID primary keys
```

**Type**: `:id | :binary_id`
**Default**: `:id`

#### `foreign_key_type`

Defines the foreign key type for Lotus tables.

```elixir
config :lotus,
  foreign_key_type: :id        # Integer foreign keys
  # or
  foreign_key_type: :binary_id # Binary ID foreign keys
```

**Type**: `:id | :binary_id`
**Default**: `:id`

### Behavior Options

#### `unique_names`

Determines whether query names must be unique across all saved queries.

```elixir
config :lotus,
  unique_names: true   # Enforce unique names (recommended)
  # or
  unique_names: false  # Allow duplicate names
```

**Type**: `boolean()`
**Default**: `true`

> **⚠️ Important**: The default Lotus migration creates a unique index on query names. If you want to allow duplicate names (`unique_names: false`), you must remove this constraint from your database.

**To allow duplicate query names:**

1. Set `unique_names: false` in your configuration
2. Create a migration to drop the unique constraint:

```elixir
defmodule MyApp.Repo.Migrations.RemoveLotusUniqueNameConstraint do
  use Ecto.Migration

  def up do
    drop_if_exists(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    create(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
  end

  def down do
    drop_if_exists(index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
    create(unique_index(:lotus_queries, [:name], name: "lotus_queries_name_index"))
  end
end
```

3. Run the migration: `mix ecto.migrate`

## Execution Options

While not part of application configuration, Lotus supports runtime options for query execution:

### Timeout Options

```elixir
# Default timeout (5 seconds)
Lotus.run_query(query)

# Custom timeout
Lotus.run_query(query, timeout: 30_000)  # 30 seconds

# Statement-level timeout (PostgreSQL)
Lotus.run_query(query, statement_timeout_ms: 15_000)  # 15 seconds
```

### Connection Options

```elixir
# Use specific schema prefix
Lotus.run_query(query, prefix: "analytics")
```

## Validation

Lotus validates your configuration at startup. Common validation errors:

### Missing Repository

```elixir
# This will raise ArgumentError during compilation
config :lotus
  # repo: MyApp.Repo  # Missing!
```

**Error**: `Invalid :lotus config: required :ecto_repo option not found, received options: []`

### Invalid Key Types

```elixir
config :lotus,
  repo: MyApp.Repo,
  primary_key_type: :uuid  # Invalid! Must be :id or :binary_id
```

**Error**: `Invalid :lotus config: invalid value for :primary_key_type option: expected one of [:id, :binary_id], got: :uuid`

## Configuration Helpers

Lotus provides helper functions to access configuration at runtime:

```elixir
# Get the configured repository
Lotus.repo()
# MyApp.Repo

# Get primary key type
Lotus.primary_key_type()
# :id

# Get foreign key type
Lotus.foreign_key_type()
# :id

# Check if unique names are enforced
Lotus.unique_names?()
# true
```

## Migration Configuration

When running migrations, the key types affect the generated schema:

### Integer Keys

```elixir
# With primary_key_type: :id, foreign_key_type: :id
create table(:lotus_queries, primary_key: false) do
  add(:id, :bigserial, primary_key: true)
  add(:name, :string, null: false)
  add(:query, :map, null: false)

  timestamps(type: :utc_datetime)
end
```

