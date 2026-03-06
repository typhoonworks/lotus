# Telemetry

Lotus emits [`:telemetry`](https://hex.pm/packages/telemetry) events for query
execution, cache operations, and schema introspection. These events integrate
with monitoring tools like Phoenix LiveDashboard, AppSignal, Datadog, and others.

## Events

### Query Execution

| Event                         | Measurements                   | Metadata                                      |
|-------------------------------|--------------------------------|-----------------------------------------------|
| `[:lotus, :query, :start]`    | `system_time`                  | `repo`, `sql`, `params`                       |
| `[:lotus, :query, :stop]`     | `duration`, `row_count`        | `repo`, `sql`, `params`, `result`             |
| `[:lotus, :query, :exception]`| `duration`                     | `repo`, `sql`, `params`, `kind`, `reason`, `stacktrace` |

Duration is measured in native time units. Use `System.convert_time_unit/3` to
convert to milliseconds or microseconds.

### Cache Operations

| Event                      | Measurements | Metadata       |
|----------------------------|--------------|----------------|
| `[:lotus, :cache, :hit]`   | `count`      | `key`          |
| `[:lotus, :cache, :miss]`  | `count`      | `key`          |
| `[:lotus, :cache, :put]`   | `count`      | `key`, `ttl_ms`|

### Schema Introspection

| Event                                       | Measurements  | Metadata                    |
|---------------------------------------------|---------------|-----------------------------|
| `[:lotus, :schema, :introspection, :start]` | `system_time` | `operation`, `repo`         |
| `[:lotus, :schema, :introspection, :stop]`  | `duration`    | `operation`, `repo`, `result` |

The `operation` field is one of: `:list_schemas`, `:list_tables`,
`:get_table_schema`, `:get_table_stats`, or `:list_relations`.

## Setup

Attach handlers in your application's `start/2` callback:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  :telemetry.attach_many(
    "lotus-telemetry",
    [
      [:lotus, :query, :stop],
      [:lotus, :query, :exception],
      [:lotus, :cache, :hit],
      [:lotus, :cache, :miss]
    ],
    &MyApp.LotusInstrumentation.handle_event/4,
    nil
  )

  children = [
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Example Handler

```elixir
defmodule MyApp.LotusInstrumentation do
  require Logger

  def handle_event([:lotus, :query, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "Lotus query completed",
      duration_ms: duration_ms,
      row_count: measurements.row_count,
      repo: inspect(metadata.repo)
    )
  end

  def handle_event([:lotus, :query, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "Lotus query failed",
      duration_ms: duration_ms,
      reason: inspect(metadata.reason),
      repo: inspect(metadata.repo)
    )
  end

  def handle_event([:lotus, :cache, :hit], _measurements, metadata, _config) do
    Logger.debug("Lotus cache hit", key: metadata.key)
  end

  def handle_event([:lotus, :cache, :miss], _measurements, metadata, _config) do
    Logger.debug("Lotus cache miss", key: metadata.key)
  end
end
```

## Phoenix LiveDashboard Integration

If you use [Phoenix LiveDashboard](https://hex.pm/packages/phoenix_live_dashboard),
you can add Lotus metrics to your telemetry supervisor:

```elixir
# lib/my_app_web/telemetry.ex
defp metrics do
  [
    # Lotus query metrics
    summary("lotus.query.stop.duration",
      unit: {:native, :millisecond},
      description: "Lotus query execution time"
    ),
    counter("lotus.query.stop.duration",
      description: "Total Lotus queries executed"
    ),
    counter("lotus.query.exception.duration",
      description: "Total Lotus query failures"
    ),

    # Cache metrics
    counter("lotus.cache.hit.count",
      description: "Lotus cache hits"
    ),
    counter("lotus.cache.miss.count",
      description: "Lotus cache misses"
    )
  ]
end
```

## Event Reference

For the complete list of events, measurements, and metadata fields, see
`Lotus.Telemetry`.
