defmodule Lotus.AI do
  @moduledoc """
  AI-powered query generation for Lotus.

  ## Configuration

  Configure AI in your application config:

      config :lotus,
        ai: [
          enabled: true,
          provider: "anthropic",
          api_key: {:system, "ANTHROPIC_API_KEY"},
          model: "claude-opus-4"
        ]

  ## Usage

      {:ok, result} = Lotus.AI.generate_query(
        prompt: "Show me all users who signed up last month",
        data_source: "postgres"
      )

      # Returns:
      # %{
      #   sql: "SELECT * FROM users WHERE created_at >= ...",
      #   variables: [],
      #   provider: "openai",
      #   model: "gpt-4o",
      #   usage: %{total_tokens: 150}
      # }

  ## Supported Providers

  - **OpenAI**: GPT-4o, GPT-4, GPT-3.5 Turbo
  - **Anthropic**: Claude Opus 4, Claude Sonnet, Claude Haiku
  - **Gemini**: Gemini 2.0 Flash, Gemini Pro

  ## Error Handling

  The `generate_query/1` function returns structured error tuples that clients can
  pattern match on for custom handling and internationalization (i18n):

  - `{:ok, result}` - Successfully generated SQL query
  - `{:error, :not_configured}` - AI features not enabled in config
  - `{:error, :api_key_not_configured}` - API key missing or invalid
  - `{:error, :unknown_provider}` - Unsupported provider
  - `{:error, {:unable_to_generate, reason}}` - LLM refused (non-SQL question)
  - `{:error, term}` - Other errors (API failures, network issues, etc.)
  """

  alias Lotus.AI.ProviderRegistry

  @doc """
  Generate SQL query from natural language prompt with conversation context.

  Enables multi-turn conversations by accepting conversation history. The AI
  can refine queries, fix errors, and provide iterative improvements.

  ## Options

  - `:prompt` (required) - Natural language description of desired query
  - `:data_source` (required) - Name of the data source to query against
  - `:conversation` (optional) - Conversation struct with message history

  ## Returns

  - `{:ok, result}` - Successfully generated SQL with metadata
  - `{:error, term}` - Structured error tuple (see module docs for error types)

  ## Examples

      # Simple single-turn (same as generate_query/1)
      {:ok, result} = Lotus.AI.generate_query_with_context(
        prompt: "Show active users",
        data_source: "postgres"
      )

      # Multi-turn with conversation history
      conversation = Conversation.new()
      conversation = Conversation.add_user_message(conversation, "Show active users")

      {:ok, result} = Lotus.AI.generate_query_with_context(
        prompt: "Show active users",
        data_source: "postgres",
        conversation: conversation
      )

      # If query fails, add error to conversation
      conversation = Conversation.add_query_result(conversation, {:error, "column 'status' not found"})

      # AI can now fix the error with full context
      {:ok, fixed_result} = Lotus.AI.generate_query_with_context(
        prompt: "Fix the error",
        data_source: "postgres",
        conversation: conversation
      )
  """
  @spec generate_query_with_context(keyword()) :: {:ok, map()} | {:error, term()}
  def generate_query_with_context(opts) do
    with {:ok, config} <- get_ai_config(),
         {:ok, provider_module} <- ProviderRegistry.get_provider(config.provider),
         {:ok, response} <-
           provider_module.generate_sql(
             prompt: opts[:prompt],
             data_source: opts[:data_source],
             conversation: opts[:conversation],
             config: config
           ) do
      {:ok,
       %{
         sql: response.content,
         variables: Map.get(response, :variables, []),
         provider: config.provider,
         model: response.model,
         usage: response.usage
       }}
    end
  end

  @doc """
  Generate SQL query from natural language prompt.

  Uses the globally configured AI provider from application config.

  ## Options

  - `:prompt` (required) - Natural language description of desired query
  - `:data_source` (required) - Name of the data source to query against

  ## Returns

  - `{:ok, result}` - Successfully generated SQL with metadata
  - `{:error, term}` - Structured error tuple (see module docs for error types)

  ## Examples

      {:ok, result} = Lotus.AI.generate_query(
        prompt: "Count active users by signup month",
        data_source: "postgres"
      )

      result.sql
      # => "SELECT DATE_TRUNC('month', created_at) as month, COUNT(*) FROM users WHERE status = 'active' GROUP BY month"

      result.provider
      # => "openai"

      result.usage
      # => %{prompt_tokens: 150, completion_tokens: 50, total_tokens: 200}

      # Error handling with pattern matching
      {:error, :not_configured} = Lotus.AI.generate_query(
        prompt: "some query",
        data_source: "postgres"
      )
  """
  @spec generate_query(keyword()) :: {:ok, map()} | {:error, term()}
  def generate_query(opts) do
    with {:ok, config} <- get_ai_config(),
         {:ok, provider_module} <- ProviderRegistry.get_provider(config.provider),
         {:ok, response} <-
           provider_module.generate_sql(
             prompt: opts[:prompt],
             data_source: opts[:data_source],
             config: config
           ) do
      {:ok,
       %{
         sql: response.content,
         variables: Map.get(response, :variables, []),
         provider: config.provider,
         model: response.model,
         usage: response.usage
       }}
    end
  end

  @doc """
  Check if AI features are enabled and configured.

  Returns `true` if AI is properly configured, `false` otherwise.

  ## Examples

      Lotus.AI.enabled?()
      # => true
  """
  @spec enabled?() :: boolean()
  def enabled? do
    case get_ai_config() do
      {:ok, _config} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get the configured AI provider name.

  Returns `{:ok, provider_name}` if configured, `{:error, :not_configured}` otherwise.

  ## Examples

      Lotus.AI.provider()
      # => {:ok, "openai"}
  """
  @spec provider() :: {:ok, String.t()} | {:error, :not_configured}
  def provider do
    case get_ai_config() do
      {:ok, config} -> {:ok, config.provider}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the configured AI model.

  Returns the model name if configured, provider's default model otherwise.

  ## Examples

      Lotus.AI.model()
      # => {:ok, "gpt-4o"}
  """
  @spec model() :: {:ok, String.t()} | {:error, :not_configured}
  def model do
    with {:ok, config} <- get_ai_config(),
         {:ok, provider_module} <- ProviderRegistry.get_provider(config.provider) do
      {:ok, config[:model] || provider_module.default_model()}
    end
  end

  defp get_ai_config do
    ai_config = Lotus.Config.get(:ai) || []

    if ai_config[:enabled] do
      provider_name = ai_config[:provider] || "openai"

      case ProviderRegistry.get_provider(provider_name) do
        {:ok, _} ->
          api_key = resolve_secret(ai_config[:api_key])

          if api_key do
            {:ok,
             %{
               provider: provider_name,
               api_key: api_key,
               model: ai_config[:model]
             }}
          else
            {:error, :api_key_not_configured}
          end

        {:error, :unknown_provider} ->
          {:error, :unknown_provider}
      end
    else
      {:error, :not_configured}
    end
  end

  defp resolve_secret({:system, env_var}) when is_binary(env_var) do
    System.get_env(env_var)
  end

  defp resolve_secret(value) when is_binary(value), do: value
  defp resolve_secret(_), do: nil
end
