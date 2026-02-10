# AI Query Generation

> ⚠️ **Experimental Feature**: This feature is experimental and disabled by default. The API may change in future versions.

Lotus includes experimental support for generating SQL queries from natural language descriptions using Large Language Models (LLMs). This guide covers setup, usage, and best practices.

## Overview

The AI query generation feature:

- **Disabled by default** - Requires explicit configuration
- **BYOK (Bring Your Own Key)** - You provide API keys and pay for usage directly
- **Schema-aware** - Introspects your database structure automatically
- **Respects visibility** - Only sees tables/columns allowed by your Lotus visibility rules
- **Read-only** - Inherits Lotus's read-only execution guarantees
- **Multi-provider** - Supports OpenAI, Anthropic (Claude), and Google Gemini

## Supported Providers

| Provider | Models | Default Model |
|----------|--------|---------------|
| OpenAI | GPT-4, GPT-4o, GPT-3.5 Turbo | `gpt-4o` |
| Anthropic | Claude Opus, Sonnet, Haiku | `claude-opus-4` |
| Google | Gemini Pro, Gemini Flash | `gemini-2.0-flash-exp` |

## Installation

Lotus includes the `langchain` dependency automatically (v0.12+). No additional packages needed.

## Configuration

### Basic Setup

Configure in your `config/config.exs` or `config/runtime.exs`:

```elixir
config :lotus, :ai,
  enabled: true,
  provider: "openai",  # or "anthropic" or "gemini"
  api_key: {:system, "OPENAI_API_KEY"}
```

### Using Environment Variables (Recommended)

```elixir
# config/runtime.exs
config :lotus, :ai,
  enabled: true,
  provider: System.get_env("AI_PROVIDER", "openai"),
  api_key: System.get_env("AI_API_KEY")
```

Then set environment variables:

```bash
export AI_PROVIDER=openai
export AI_API_KEY=sk-proj-...
```

### Provider-Specific Setup

#### OpenAI

```elixir
config :lotus, :ai,
  enabled: true,
  provider: "openai",
  api_key: {:system, "OPENAI_API_KEY"},
  model: "gpt-4o"  # optional, defaults to "gpt-4o"
```

Get your API key from: https://platform.openai.com/api-keys

#### Anthropic (Claude)

```elixir
config :lotus, :ai,
  enabled: true,
  provider: "anthropic",
  api_key: {:system, "ANTHROPIC_API_KEY"},
  model: "claude-opus-4"  # optional
```

Get your API key from: https://console.anthropic.com/settings/keys

#### Google Gemini

```elixir
config :lotus, :ai,
  enabled: true,
  provider: "gemini",
  api_key: {:system, "GOOGLE_AI_KEY"},
  model: "gemini-2.0-flash-exp"  # optional
```

Get your API key from: https://aistudio.google.com/app/apikey

## Usage

### Basic Query Generation

```elixir
{:ok, result} = Lotus.AI.generate_query(
  prompt: "Show all users who signed up in the last 7 days",
  data_source: "my_repo"
)

result.sql
#=> "SELECT * FROM users WHERE created_at > NOW() - INTERVAL '7 days'"

result.model
#=> "gpt-4o"

result.usage
#=> %{prompt_tokens: 245, completion_tokens: 28, total_tokens: 273}
```

### Error Handling

```elixir
case Lotus.AI.generate_query(prompt: prompt, data_source: repo) do
  {:ok, result} ->
    # Success - use result.sql

  {:error, :not_configured} ->
    # AI features not enabled in config

  {:error, :api_key_not_configured} ->
    # API key missing or invalid

  {:error, {:unable_to_generate, reason}} ->
    # LLM couldn't generate query (e.g., "This is a weather question")

  {:error, reason} ->
    # Other error (network, timeout, etc.)
end
```

### Complex Queries

The AI uses multiple tools to understand your schema:

```elixir
# Complex query with joins across schemas
Lotus.AI.generate_query(
  prompt: "Which customers have outstanding invoices with their total amount owed",
  data_source: "analytics_db"
)

# Behind the scenes, the AI will:
# 1. Call list_schemas() to find "reporting" schema
# 2. Call list_tables() to find "customers" and "invoices" tables
# 3. Call get_table_schema() for both tables
# 4. Call get_column_values("invoices", "status") to check valid statuses
# 5. Generate: SELECT c.name, SUM(i.amount) FROM reporting.customers c ...
```

## How It Works

### Schema Introspection Tools

The AI has access to four tools:

1. **`list_schemas()`** - Get all database schemas
2. **`list_tables()`** - Get tables with schema-qualified names
3. **`get_table_schema(table_name)`** - Get columns, types, constraints
4. **`get_column_values(table_name, column_name)`** - Get distinct values (enums, statuses)

All tools respect your Lotus visibility rules - the AI sees exactly what your users see.

### Query Generation Process

1. **Parse prompt** - LLM analyzes the natural language request
2. **Discover schema** - Calls tools to find relevant tables
3. **Introspect tables** - Gets column details for identified tables
4. **Check enum values** - For status/type columns, gets actual values
5. **Generate SQL** - Produces schema-qualified, type-safe SQL

### Example: Status Value Discovery

Instead of guessing:

```sql
-- ❌ AI assumes status value
WHERE status = 'outstanding'  -- might not exist!
```

The AI checks first:

```elixir
# AI calls: get_column_values("invoices", "status")
# Returns: ["open", "paid", "overdue"]

# Then generates:
WHERE status IN ('open', 'overdue')  -- ✅ uses actual values
```

## Best Practices

### 1. Use Descriptive Prompts

**Good:**
- "Show customers with unpaid invoices sorted by amount owed"
- "Find users who haven't logged in during the last 30 days"
- "Calculate monthly revenue from the orders table"

**Too Vague:**
- "Show me some data" ❌
- "Users" ❌

### 2. Mention Specific Tables

Help the AI by referencing table names:

```elixir
"Show sales from the orders table grouped by month"
```

### 3. Specify Time Ranges

Be clear about dates:

```elixir
"Users created in the last 7 days"  # ✅
"Recent users"  # ❌ ambiguous
```

### 4. Review Generated Queries

Always review the generated SQL before using it in production:

```elixir
{:ok, result} = Lotus.AI.generate_query(prompt: prompt, data_source: repo)

IO.puts("Generated SQL:")
IO.puts(result.sql)

# Review before executing:
Lotus.run_sql(result.sql, [], repo: repo)
```

## Visibility and Security

### AI Respects Visibility Rules

The AI assistant only sees what your Lotus visibility configuration allows:

```elixir
# config/config.exs
config :lotus,
  table_visibility: %{
    default: [
      deny: [
        {"public", "api_keys"},      # ✅ Hidden from AI
        {"public", "user_sessions"}   # ✅ Hidden from AI
      ]
    ]
  }
```

If a user asks "Show me all API keys", the AI will respond:

```
UNABLE_TO_GENERATE: api_keys table not available
```

### Read-Only Execution

All AI-generated queries inherit Lotus's read-only guarantees:

- Queries run in read-only transactions
- `INSERT`, `UPDATE`, `DELETE` statements are blocked
- DDL commands (`CREATE`, `DROP`, `ALTER`) are blocked

## Cost Management

### Token Usage

Each query generation consumes tokens from your API provider. Check your usage:

```elixir
{:ok, result} = Lotus.AI.generate_query(...)

result.usage
#=> %{
#=>   prompt_tokens: 450,      # Input (schema info + prompt)
#=>   completion_tokens: 42,   # Output (generated SQL)
#=>   total_tokens: 492
#=> }
```

Refer to your provider's pricing page for current rates.

### Reducing Token Usage

1. **Use cheaper models** for simple queries
2. **Be specific in prompts** to minimize tool calls

## Troubleshooting

### "AI features are not configured"

Enable AI in your config:

```elixir
config :lotus, :ai,
  enabled: true,
  provider: "openai",
  api_key: "sk-..."
```

### "API key is missing or invalid"

Check your API key:

```elixir
# Verify environment variable is set
System.get_env("OPENAI_API_KEY")

# Or check config
Application.get_env(:lotus, :ai)
```

### "Unable to generate query: ..."

The LLM refused to generate SQL. Common reasons:

- Question not related to database ("What's the weather?")
- Required tables not visible
- Ambiguous or incomplete prompt

### Queries are slow

AI query generation typically takes 2-10 seconds depending on:

- Database complexity (more tables = more tool calls)
- LLM provider and model
- Network latency

## Limitations

- **No query history** - Each generation is independent
- **No multi-turn refinement** - Can't iteratively improve queries
- **English prompts recommended** - Other languages may work but aren't tested

## API Reference

### `Lotus.AI.generate_query/1`

Generates SQL from natural language.

**Options:**

- `:prompt` (required) - Natural language description
- `:data_source` (required) - Repository name or module

**Returns:**

- `{:ok, %{sql: String.t(), model: String.t(), usage: map()}}` - Success
- `{:error, :not_configured}` - AI not enabled
- `{:error, :api_key_not_configured}` - Missing API key
- `{:error, {:unable_to_generate, reason}}` - LLM refused
- `{:error, term()}` - Other error

### `Lotus.AI.enabled?/0`

Checks if AI features are enabled.

```elixir
if Lotus.AI.enabled?() do
  # Show AI button in UI
end
```

