# Dashboards

Dashboards let you combine multiple queries into interactive, shareable views. They're ideal for building reporting interfaces, KPI displays, and data exploration tools.

## Overview

A dashboard consists of:

- **Cards** - Individual content blocks arranged in a grid
- **Filters** - Input controls that affect multiple cards simultaneously
- **Filter mappings** - Connections between filters and query variables

## Creating a Dashboard

```elixir
{:ok, dashboard} = Lotus.create_dashboard(%{
  name: "Sales Overview",
  description: "Key sales metrics and trends"
})
```

### Dashboard Settings

The `settings` field stores UI preferences as a map:

```elixir
Lotus.update_dashboard(dashboard, %{
  settings: %{
    "theme" => "dark",
    "columns" => 12
  }
})
```

### Auto-refresh

Enable periodic refresh by setting `auto_refresh_seconds` (minimum 60):

```elixir
Lotus.update_dashboard(dashboard, %{auto_refresh_seconds: 300})  # 5 minutes
```

## Working with Cards

Cards are the building blocks of dashboards. Each card occupies a position in a 12-column grid.

### Card Types

| Type | Description |
|------|-------------|
| `:query` | Displays results from a saved query |
| `:text` | Markdown text content |
| `:heading` | Section header |
| `:link` | Clickable link to external resource |

### Adding a Query Card

```elixir
# First, get or create a query
{:ok, query} = Lotus.create_query(%{
  name: "Monthly Revenue",
  statement: "SELECT date_trunc('month', created_at) as month, SUM(amount) as revenue FROM orders GROUP BY 1"
})

# Add it to the dashboard
{:ok, card} = Lotus.create_dashboard_card(dashboard, %{
  card_type: :query,
  query_id: query.id,
  title: "Revenue by Month",
  position: 0,
  layout: %{x: 0, y: 0, w: 6, h: 4}
})
```

### Layout System

Cards use a 12-column grid with these layout properties:

- `x` - Column position (0-11)
- `y` - Row position (0+)
- `w` - Width in columns (1-12)
- `h` - Height in rows (minimum 2)

```elixir
# Full-width card at top
%{x: 0, y: 0, w: 12, h: 3}

# Two half-width cards side by side
%{x: 0, y: 3, w: 6, h: 4}  # Left
%{x: 6, y: 3, w: 6, h: 4}  # Right
```

### Text and Heading Cards

```elixir
# Add a section heading
{:ok, _} = Lotus.create_dashboard_card(dashboard, %{
  card_type: :heading,
  content: %{"text" => "Key Metrics"},
  position: 0,
  layout: %{x: 0, y: 0, w: 12, h: 1}
})

# Add explanatory text
{:ok, _} = Lotus.create_dashboard_card(dashboard, %{
  card_type: :text,
  content: %{"markdown" => "Revenue figures are **updated daily** at midnight UTC."},
  position: 1,
  layout: %{x: 0, y: 1, w: 12, h: 2}
})
```

### Visualization Overrides

Query cards can override the query's default visualization:

```elixir
Lotus.update_dashboard_card(card, %{
  visualization_config: %{
    "type" => "bar",
    "x_field" => "month",
    "y_field" => "revenue"
  }
})
```

## Dashboard Filters

Filters provide input controls that affect multiple cards. When a user changes a filter value, it's passed to the mapped query variables.

### Filter Types

| Type | Widget Options | Description |
|------|----------------|-------------|
| `:text` | `:input`, `:select` | Free-form text |
| `:number` | `:input`, `:select` | Numeric values |
| `:date` | `:date_picker`, `:input` | Single date |
| `:date_range` | `:date_range_picker` | Start and end dates |
| `:select` | `:select` | Dropdown selection |

### Creating Filters

```elixir
{:ok, date_filter} = Lotus.create_dashboard_filter(dashboard, %{
  name: "date_range",
  label: "Date Range",
  filter_type: :date_range,
  widget: :date_range_picker,
  default_value: "last_30_days",
  position: 0
})

{:ok, region_filter} = Lotus.create_dashboard_filter(dashboard, %{
  name: "region",
  label: "Region",
  filter_type: :select,
  widget: :select,
  config: %{
    "options" => [
      %{"value" => "us", "label" => "United States"},
      %{"value" => "eu", "label" => "Europe"},
      %{"value" => "apac", "label" => "Asia Pacific"}
    ]
  },
  position: 1
})
```

### Mapping Filters to Query Variables

Connect filters to query variables using filter mappings:

```elixir
# Map date_range filter to the "start_date" variable in a card's query
Lotus.create_filter_mapping(card, date_filter, "start_date")

# Map region filter to "region" variable
Lotus.create_filter_mapping(card, region_filter, "region")
```

A single filter can map to different variable names across cards:

```elixir
# Same filter, different variable names per card
Lotus.create_filter_mapping(orders_card, date_filter, "order_date")
Lotus.create_filter_mapping(revenue_card, date_filter, "transaction_date")
```

### Transform Configuration

For complex mappings (like splitting a date range), use the `transform` option:

```elixir
Lotus.create_filter_mapping(card, date_filter, "start_date",
  transform: %{"type" => "date_range_start"}
)

Lotus.create_filter_mapping(card, date_filter, "end_date",
  transform: %{"type" => "date_range_end"}
)
```

## Running Dashboards

Execute all cards in a dashboard with a single call:

```elixir
{:ok, results} = Lotus.run_dashboard(dashboard)
# => %{card_id => {:ok, %Lotus.Result{}} | {:error, reason}}
```

### With Filter Values

Pass current filter values to override defaults:

```elixir
{:ok, results} = Lotus.run_dashboard(dashboard,
  filter_values: %{
    "date_range" => "2024-01-01/2024-03-31",
    "region" => "us"
  }
)
```

### Execution Options

| Option | Description |
|--------|-------------|
| `:filter_values` | Map of filter name to value |
| `:timeout` | Per-card timeout in milliseconds (default: 30000) |
| `:parallel` | Run cards in parallel (default: true) |

### Running Individual Cards

Execute a single card:

```elixir
{:ok, result} = Lotus.run_dashboard_card(card,
  filter_values: %{"region" => "eu"}
)
```

## Public Sharing

Share dashboards via secure public links.

### Enable Sharing

```elixir
{:ok, dashboard} = Lotus.enable_public_sharing(dashboard)
# dashboard.public_token => "abc123..."
```

### Access by Token

```elixir
case Lotus.get_dashboard_by_token("abc123...") do
  nil -> :not_found
  dashboard -> Lotus.run_dashboard(dashboard)
end
```

### Disable Sharing

```elixir
{:ok, dashboard} = Lotus.disable_public_sharing(dashboard)
# dashboard.public_token => nil
```

## Exporting Dashboards

Export all card results to a ZIP file with one CSV per card:

```elixir
{:ok, zip_binary} = Lotus.export_dashboard(dashboard,
  filter_values: %{"region" => "us"}
)

File.write!("sales_report.zip", zip_binary)
```

The ZIP contains files named `{position}_{card_title}.csv` for each query card.

## Database Migration

Dashboards require migration V3. Run the migration to add the necessary tables:

```elixir
Lotus.Migrations.up(MyApp.Repo)
```

This creates:
- `lotus_dashboards`
- `lotus_dashboard_cards`
- `lotus_dashboard_filters`
- `lotus_dashboard_card_filter_mappings`

## Example: Sales Dashboard

```elixir
# Create dashboard
{:ok, dashboard} = Lotus.create_dashboard(%{
  name: "Sales Dashboard",
  description: "Daily sales metrics"
})

# Add date filter
{:ok, date_filter} = Lotus.create_dashboard_filter(dashboard, %{
  name: "period",
  label: "Time Period",
  filter_type: :date_range,
  widget: :date_range_picker,
  position: 0
})

# Create queries
{:ok, revenue_query} = Lotus.create_query(%{
  name: "Daily Revenue",
  statement: """
  SELECT date, SUM(amount) as revenue
  FROM orders
  WHERE date BETWEEN {{start_date}} AND {{end_date}}
  GROUP BY date
  """
})

{:ok, orders_query} = Lotus.create_query(%{
  name: "Order Count",
  statement: """
  SELECT COUNT(*) as total
  FROM orders
  WHERE created_at BETWEEN {{from}} AND {{to}}
  """
})

# Add cards
{:ok, revenue_card} = Lotus.create_dashboard_card(dashboard, %{
  card_type: :query,
  query_id: revenue_query.id,
  title: "Revenue Trend",
  position: 0,
  layout: %{x: 0, y: 0, w: 8, h: 4}
})

{:ok, orders_card} = Lotus.create_dashboard_card(dashboard, %{
  card_type: :query,
  query_id: orders_query.id,
  title: "Total Orders",
  position: 1,
  layout: %{x: 8, y: 0, w: 4, h: 4}
})

# Map filter to both cards (with different variable names)
Lotus.create_filter_mapping(revenue_card, date_filter, "start_date",
  transform: %{"type" => "date_range_start"}
)
Lotus.create_filter_mapping(revenue_card, date_filter, "end_date",
  transform: %{"type" => "date_range_end"}
)

Lotus.create_filter_mapping(orders_card, date_filter, "from",
  transform: %{"type" => "date_range_start"}
)
Lotus.create_filter_mapping(orders_card, date_filter, "to",
  transform: %{"type" => "date_range_end"}
)

# Run the dashboard
{:ok, results} = Lotus.run_dashboard(dashboard,
  filter_values: %{"period" => "2024-01-01/2024-01-31"}
)
```
