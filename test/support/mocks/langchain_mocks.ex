defmodule Lotus.LangChainMocks do
  @moduledoc """
  Mimic-based mocks for LangChain modules.

  Provides mocks for testing AI provider integrations without calling real APIs.
  """

  import Mimic
  import Lotus.AIFixtures

  alias LangChain.Message
  alias LangChain.TokenUsage

  @doc """
  Setup Mimic copies for LangChain modules.

  Call this in test setup blocks before using LangChain mocks.
  """
  def setup_mocks do
    Mimic.copy(LangChain.Chains.LLMChain)
  end

  @doc """
  Mock successful SQL generation from LLM.

  Returns a canned successful response with SQL in markdown format.
  """
  def mock_successful_generation do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      {:ok, build_chain_response(chain, successful_sql_response())}
    end)
  end

  @doc """
  Mock LLM refusing to generate SQL (non-SQL question).

  Returns response with UNABLE_TO_GENERATE marker.
  """
  def mock_unable_to_generate do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      {:ok, build_chain_response(chain, unable_to_generate_response())}
    end)
  end

  @doc """
  Mock plain SQL response without markdown wrapper.
  """
  def mock_plain_sql do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      {:ok, build_chain_response(chain, plain_sql_response())}
    end)
  end

  @doc """
  Mock complex SQL with JOINs.
  """
  def mock_complex_sql do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      {:ok, build_chain_response(chain, complex_sql_response())}
    end)
  end

  @doc """
  Mock API error (rate limiting, auth failure, etc.).
  """
  def mock_api_error(error_message \\ "Rate limit exceeded") do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      {:error, chain, error_message}
    end)
  end

  @doc """
  Mock network timeout.
  """
  def mock_timeout do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      {:error, chain, :timeout}
    end)
  end

  @doc """
  Mock successful generation with assertion on chain parameters.

  Useful for verifying that the correct model, temperature, tools, etc. are passed.
  """
  def mock_with_assertion(assertion_fn) when is_function(assertion_fn, 1) do
    expect(LangChain.Chains.LLMChain, :run, fn chain ->
      assertion_fn.(chain)
      {:ok, build_chain_response(chain, successful_sql_response())}
    end)
  end

  defp build_chain_response(chain, response_fixture) do
    # Convert fixture usage map to TokenUsage struct
    usage = build_token_usage(response_fixture.usage)

    # Build message with content and metadata
    message = %Message{
      role: :assistant,
      content: response_fixture.content,
      metadata: %{usage: usage}
    }

    # Return updated chain with last_message set
    %{chain | last_message: message}
  end

  defp build_token_usage(usage_map) do
    # Handle different provider token formats
    input =
      usage_map["prompt_tokens"] || usage_map["input_tokens"] ||
        usage_map["promptTokenCount"] || 0

    output =
      usage_map["completion_tokens"] || usage_map["output_tokens"] ||
        usage_map["candidatesTokenCount"] || 0

    %TokenUsage{
      input: input,
      output: output,
      raw: usage_map
    }
  end
end
