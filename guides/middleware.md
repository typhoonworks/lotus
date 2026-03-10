# Middleware

Lotus provides a middleware pipeline that lets you hook into query execution and schema discovery events. Middleware follows the familiar Plug pattern — each module implements `init/1` and `call/2`.

## How It Works

A middleware module looks like this:

```elixir
defmodule MyApp.AuditMiddleware do
  def init(opts), do: opts

  def call(payload, _opts) do
    # Inspect or transform the payload
    {:cont, payload}   # continue to next middleware
    # or
    {:halt, "reason"}  # stop pipeline, Lotus returns {:error, reason}
  end
end
```

Each middleware receives a payload map whose contents depend on the pipeline event (see below), and must return either `{:cont, payload}` to continue or `{:halt, reason}` to abort.

## Pipeline Events

| Event | Triggered | Payload keys |
|-------|-----------|--------------|
| `:before_query` | After preflight visibility check, before SQL execution | `:sql`, `:params`, `:repo`, `:context` |
| `:after_query` | After execution, before result returned to caller | `:result`, `:sql`, `:params`, `:repo`, `:context` |
| `:after_list_schemas` | After schema discovery and visibility filtering | `:schemas`, `:repo`, `:context` |
| `:after_list_tables` | After table discovery and visibility filtering | `:tables`, `:repo`, `:context` |
| `:after_get_table_schema` | After table schema introspection and column visibility | `:table_schema`, `:repo`, `:context` |
| `:after_list_relations` | After relation discovery and visibility filtering | `:relations`, `:repo`, `:context` |

## Configuration

Register middleware in your Lotus config. Each entry is a `{module, opts}` tuple — `opts` is passed to `init/1` at compile time:

```elixir
config :lotus,
  middleware: %{
    before_query: [
      {MyApp.AccessControlMiddleware, []},
      {MyApp.QueryAuditMiddleware, [repo: MyApp.AuditRepo]}
    ],
    after_query: [
      {MyApp.ResultRedactionMiddleware, [fields: ~w(email phone ssn)]}
    ],
    after_list_tables: [
      {MyApp.TableFilterMiddleware, []}
    ]
  }
```

Middleware runs in the order listed. Multiple middleware can be chained on the same event.

## Context

A `:context` key carries opaque user data (e.g. the current user) through to middleware. Lotus never inspects this value — it's purely for your application's use.

```elixir
# Pass context when running a query
Lotus.run_sql("SELECT * FROM orders", [], context: %{user_id: current_user.id})
```

```elixir
defmodule MyApp.AccessControlMiddleware do
  def init(opts), do: opts

  def call(%{context: %{user_id: nil}} = _payload, _opts) do
    {:halt, "authentication required"}
  end

  def call(payload, _opts) do
    {:cont, payload}
  end
end
```

## Examples

### Audit Logging

Log every query execution with the user who ran it:

```elixir
defmodule MyApp.QueryAuditMiddleware do
  require Logger

  def init(opts), do: opts

  def call(%{sql: sql, context: context} = payload, _opts) do
    user_id = Map.get(context || %{}, :user_id, "anonymous")
    Logger.info("[Lotus] user=#{user_id} sql=#{inspect(sql)}")
    {:cont, payload}
  end
end
```

### Row-Level Security

Block queries that don't include a tenant filter:

```elixir
defmodule MyApp.TenantMiddleware do
  def init(opts), do: opts

  def call(%{sql: sql, context: context} = payload, _opts) do
    tenant_id = Map.get(context || %{}, :tenant_id)

    cond do
      is_nil(tenant_id) ->
        {:halt, "tenant context required"}

      not String.contains?(String.downcase(sql), "tenant_id") ->
        {:halt, "queries must filter by tenant_id"}

      true ->
        {:cont, payload}
    end
  end
end
```

### Redacting Sensitive Data in Results

Mask PII columns (emails, phone numbers, etc.) so non-admin users only see partial values:

```elixir
defmodule MyApp.ResultRedactionMiddleware do
  @moduledoc """
  Masks sensitive columns in query results based on configurable field names.
  Admins (identified via context) see full values; everyone else sees masked output.
  """

  def init(opts), do: Keyword.get(opts, :fields, [])

  def call(%{result: result, context: context} = payload, fields) do
    if admin?(context) do
      {:cont, payload}
    else
      col_indexes =
        result.columns
        |> Enum.with_index()
        |> Enum.filter(fn {col, _i} -> col in fields end)
        |> Enum.map(fn {_col, i} -> i end)
        |> MapSet.new()

      redacted_rows =
        Enum.map(result.rows, fn row ->
          row
          |> Enum.with_index()
          |> Enum.map(fn {val, i} ->
            if i in col_indexes, do: mask(val), else: val
          end)
        end)

      {:cont, put_in(payload, [:result, Access.key(:rows)], redacted_rows)}
    end
  end

  defp admin?(%{role: :admin}), do: true
  defp admin?(_), do: false

  defp mask(val) when is_binary(val) and byte_size(val) > 4 do
    String.slice(val, 0, 2) <> String.duplicate("*", max(String.length(val) - 4, 3)) <> String.slice(val, -2, 2)
  end

  defp mask(_val), do: "****"
end
```

Configure which fields to redact:

```elixir
config :lotus,
  middleware: %{
    after_query: [
      {MyApp.ResultRedactionMiddleware, [fields: ~w(email phone ssn)]}
    ]
  }
```

A query like `SELECT name, email FROM users` would return:

| name | email |
|------|-------|
| Alice Johnson | al***************om |
| Bob Smith | bo***********om |

### Filtering Schema Discovery

Hide internal tables from the schema browser:

```elixir
defmodule MyApp.TableFilterMiddleware do
  @hidden_prefixes ["_internal_", "oban_"]

  def init(opts), do: opts

  def call(%{tables: tables} = payload, _opts) do
    filtered = Enum.reject(tables, fn table ->
      Enum.any?(@hidden_prefixes, &String.starts_with?(table.name, &1))
    end)

    {:cont, %{payload | tables: filtered}}
  end
end
```

## Halting the Pipeline

When a middleware returns `{:halt, reason}`, the pipeline stops immediately and Lotus returns `{:error, reason}` to the caller. This is useful for enforcing access control, rate limiting, or any validation that should prevent execution:

```elixir
def call(%{sql: sql} = payload, _opts) do
  if String.contains?(String.downcase(sql), "pg_sleep") do
    {:halt, "pg_sleep is not allowed"}
  else
    {:cont, payload}
  end
end
```
