defmodule Lotus.AI.SchemaOptimizer do
  @moduledoc """
  Optimizes schema loading for large databases using two-stage approach.

  For databases with 50+ tables, loading the full schema for all tables in a single
  prompt can exceed token limits and reduce accuracy. This module implements a
  two-stage strategy:

  1. **Stage 1**: Identify relevant tables from the user's query
  2. **Stage 2**: Load detailed schema only for identified tables

  This dramatically reduces token usage while improving accuracy.

  ## Usage

      # Check if optimization is needed
      if SchemaOptimizer.should_optimize?(table_count) do
        # Stage 1: Identify relevant tables
        {:ok, relevant_tables} = SchemaOptimizer.identify_relevant_tables(
          prompt: "Show sales by region",
          tables: all_table_names,
          config: ai_config
        )

        # Stage 2: Load schema only for relevant tables
        # ... proceed with normal query generation using only relevant_tables
      end

  ## Benefits

  - **Reduced tokens**: Only load schemas for relevant tables (5-10 instead of 50+)
  - **Improved accuracy**: LLM focuses on relevant schema without noise
  - **Faster generation**: Less context to process means faster responses
  - **Cost savings**: Fewer tokens = lower API costs
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatGoogleAI
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message
  alias Lotus.AI.ProviderRegistry

  @table_count_threshold 50
  @max_tables_to_identify 10

  @doc """
  Determine if schema optimization should be used.

  Returns true if the database has more than #{@table_count_threshold} tables.

  ## Examples

      iex> SchemaOptimizer.should_optimize?(25)
      false

      iex> SchemaOptimizer.should_optimize?(75)
      true
  """
  @spec should_optimize?(non_neg_integer()) :: boolean()
  def should_optimize?(table_count) do
    table_count > @table_count_threshold
  end

  @doc """
  Identify relevant tables for a given query (Stage 1).

  Uses a lightweight LLM call with just table names to identify which
  tables are likely needed for the query.

  ## Parameters

  - `opts` - Keyword list with:
    - `:prompt` (required) - User's natural language query
    - `:tables` (required) - List of all available table names
    - `:config` (required) - AI provider configuration
    - `:max_tables` (optional) - Maximum tables to identify (default: #{@max_tables_to_identify})

  ## Returns

  - `{:ok, [table_names]}` - List of relevant table names
  - `{:error, term}` - Error during identification

  ## Examples

      {:ok, tables} = SchemaOptimizer.identify_relevant_tables(
        prompt: "Show total sales by region for last month",
        tables: ["users", "orders", "products", "regions", "sales", ...],
        config: %{provider: "openai", api_key: "..."}
      )
      # => {:ok, ["sales", "regions", "orders"]}
  """
  @spec identify_relevant_tables(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def identify_relevant_tables(opts) do
    prompt = Keyword.fetch!(opts, :prompt)
    tables = Keyword.fetch!(opts, :tables)
    config = Keyword.fetch!(opts, :config)
    max_tables = Keyword.get(opts, :max_tables, @max_tables_to_identify)

    system_prompt = build_table_identification_prompt(tables, max_tables)

    case call_llm(system_prompt, prompt, config) do
      {:ok, response} ->
        identified_tables = parse_table_list(response, tables)
        {:ok, identified_tables}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp build_table_identification_prompt(tables, max_tables) do
    table_list = Enum.join(tables, "\n- ")

    """
    You are a database query assistant. Your task is to identify which tables are relevant
    for answering a user's query.

    ## Available Tables:
    - #{table_list}

    ## Instructions:
    1. Analyze the user's query
    2. Identify which tables would be needed to answer it
    3. Return ONLY the table names, one per line
    4. Return at most #{max_tables} tables
    5. Be conservative - only include tables that are clearly relevant

    ## Response Format:
    Return only table names, one per line. Do not include explanations or numbering.

    Example response:
    users
    orders
    products

    If no tables are relevant, respond with: NONE
    """
  end

  defp call_llm(system_prompt, user_prompt, config) do
    {:ok, provider_module} = ProviderRegistry.get_provider(config.provider)

    model =
      case config.provider do
        "anthropic" ->
          %ChatAnthropic{
            model: config[:model] || provider_module.default_model(),
            api_key: config.api_key,
            temperature: 0.0
          }

        "openai" ->
          %ChatOpenAI{
            model: config[:model] || provider_module.default_model(),
            api_key: config.api_key,
            temperature: 0.0
          }

        "gemini" ->
          %ChatGoogleAI{
            model: config[:model] || provider_module.default_model(),
            api_key: config.api_key,
            temperature: 0.0
          }
      end

    chain =
      LLMChain.new!(%{llm: model})
      |> LLMChain.add_messages([
        Message.new_system!(system_prompt),
        Message.new_user!(user_prompt)
      ])

    case LLMChain.run(chain) do
      {:ok, updated_chain} ->
        content = extract_content(updated_chain.last_message.content)
        {:ok, content}

      {:error, _chain, error} ->
        {:error, error}
    end
  end

  defp extract_content(text) when is_binary(text), do: text

  defp extract_content([%{type: :text, content: text} | _]), do: text

  defp extract_content(parts) when is_list(parts) do
    parts
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join("\n", & &1.content)
  end

  defp extract_content(nil), do: ""

  defp parse_table_list(response, available_tables) do
    response = String.trim(response)

    if String.upcase(response) == "NONE" do
      []
    else
      # Extract table names from response
      response
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(&extract_table_name/1)
      |> Enum.filter(&(&1 in available_tables))
      |> Enum.take(@max_tables_to_identify)
    end
  end

  # Extract table name from various formats
  defp extract_table_name(line) do
    line
    # Remove numbering (1. users, - users, etc.)
    |> String.replace(~r/^[\d\-\*\+\.]\s*/, "")
    # Remove quotes
    |> String.replace(~r/^['"`]|['"`]$/, "")
    # Remove schema qualification if present (keep just table name)
    |> then(fn name ->
      case String.split(name, ".") do
        [_schema, table] -> table
        [table] -> table
      end
    end)
    |> String.trim()
  end
end
