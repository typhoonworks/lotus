defmodule Lotus.AI.Providers.AnthropicTest do
  use Lotus.AICase, async: true

  alias Lotus.AI.Providers.Anthropic

  describe "default_model/0" do
    test "returns claude-opus-4" do
      assert Anthropic.default_model() == "claude-opus-4"
    end
  end

  describe "validate_key/1" do
    test "accepts valid non-empty string" do
      config = %{api_key: "sk-ant-test123"}

      assert :ok = Anthropic.validate_key(config)
    end

    test "accepts any non-empty string" do
      config = %{api_key: "anything-non-empty"}

      assert :ok = Anthropic.validate_key(config)
    end

    test "rejects empty string" do
      config = %{api_key: ""}

      assert {:error, _message} = Anthropic.validate_key(config)
    end
  end

  describe "generate_sql/1" do
    setup do
      setup_mocks()

      stub(Lotus.Sources, :source_type, fn _ -> :postgres end)
      stub(Lotus.Schema, :list_tables, fn _ -> {:ok, table_list()} end)

      :ok
    end

    test "generates SQL successfully with Anthropic response format" do
      # Anthropic uses input_tokens/output_tokens instead of prompt_tokens/completion_tokens
      mock_plain_sql()

      opts = [
        prompt: "Count users",
        data_source: "postgres",
        config: %{api_key: "sk-ant-test", provider: "anthropic"}
      ]

      assert {:ok, response} = Anthropic.generate_sql(opts)

      assert response.content == "SELECT COUNT(*) FROM users WHERE status = 'active'"
      assert response.model == "claude-opus-4"
      # Should correctly map Anthropic's token format
      assert response.usage.prompt_tokens == 120
      assert response.usage.completion_tokens == 30
      assert response.usage.total_tokens == 150
    end

    test "uses configured model override" do
      mock_with_assertion(fn chain ->
        assert chain.llm.model == "claude-sonnet-4"
      end)

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-ant-test", provider: "anthropic", model: "claude-sonnet-4"}
      ]

      assert {:ok, _response} = Anthropic.generate_sql(opts)
    end

    test "returns error when LLM refuses" do
      mock_unable_to_generate()

      opts = [
        prompt: "Weather question",
        data_source: "postgres",
        config: %{api_key: "sk-ant-test", provider: "anthropic"}
      ]

      assert {:error, {:unable_to_generate, _reason}} = Anthropic.generate_sql(opts)
    end
  end
end
