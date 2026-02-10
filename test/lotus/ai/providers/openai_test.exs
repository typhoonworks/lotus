defmodule Lotus.AI.Providers.OpenAITest do
  use Lotus.AICase, async: true

  alias Lotus.AI.Providers.OpenAI

  describe "default_model/0" do
    test "returns gpt-4o" do
      assert OpenAI.default_model() == "gpt-4o"
    end
  end

  describe "validate_key/1" do
    test "accepts valid non-empty string" do
      config = %{api_key: "sk-test123"}

      assert :ok = OpenAI.validate_key(config)
    end

    test "accepts any non-empty string" do
      config = %{api_key: "anything-non-empty"}

      assert :ok = OpenAI.validate_key(config)
    end

    test "rejects empty string" do
      config = %{api_key: ""}

      assert {:error, _message} = OpenAI.validate_key(config)
    end

    test "rejects nil" do
      config = %{api_key: nil}

      assert {:error, _message} = OpenAI.validate_key(config)
    end
  end

  describe "generate_sql/1" do
    setup do
      setup_mocks()

      stub(Lotus.Sources, :source_type, fn _ -> :postgres end)
      stub(Lotus.Schema, :list_tables, fn _ -> {:ok, table_list()} end)

      :ok
    end

    test "generates SQL successfully" do
      mock_successful_generation()

      opts = [
        prompt: "Show active users",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai"}
      ]

      assert {:ok, response} = OpenAI.generate_sql(opts)

      assert response.content =~ "SELECT * FROM users"
      assert response.model == "gpt-4o"
      assert response.usage.prompt_tokens == 150
      assert response.usage.completion_tokens == 50
      assert response.usage.total_tokens == 200
    end

    test "uses configured model override" do
      mock_with_assertion(fn chain ->
        assert chain.llm.model == "gpt-3.5-turbo"
      end)

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai", model: "gpt-3.5-turbo"}
      ]

      assert {:ok, _response} = OpenAI.generate_sql(opts)
    end

    test "sets low temperature for consistent SQL" do
      mock_with_assertion(fn chain ->
        assert chain.llm.temperature == 0.1
      end)

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai"}
      ]

      assert {:ok, _response} = OpenAI.generate_sql(opts)
    end

    test "passes API key to model" do
      mock_with_assertion(fn chain ->
        assert chain.llm.api_key == "sk-test123"
      end)

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-test123", provider: "openai"}
      ]

      assert {:ok, _response} = OpenAI.generate_sql(opts)
    end

    test "includes schema query tools" do
      mock_with_assertion(fn chain ->
        assert length(chain.tools) == 4

        tool_names = Enum.map(chain.tools, & &1.name)
        assert "list_schemas" in tool_names
        assert "list_tables" in tool_names
        assert "get_table_schema" in tool_names
        assert "get_column_values" in tool_names
      end)

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai"}
      ]

      assert {:ok, _response} = OpenAI.generate_sql(opts)
    end

    test "returns structured error when LLM refuses" do
      mock_unable_to_generate()

      opts = [
        prompt: "What's the weather?",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai"}
      ]

      assert {:error, {:unable_to_generate, reason}} = OpenAI.generate_sql(opts)
      assert reason == "This is a weather question, not a database query"
    end

    test "returns error when API fails" do
      mock_api_error("Invalid API key")

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-invalid", provider: "openai"}
      ]

      assert {:error, "Invalid API key"} = OpenAI.generate_sql(opts)
    end

    test "returns error when request times out" do
      mock_timeout()

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai"}
      ]

      assert {:error, :timeout} = OpenAI.generate_sql(opts)
    end

    test "extracts plain SQL without markdown" do
      mock_plain_sql()

      opts = [
        prompt: "Count users",
        data_source: "postgres",
        config: %{api_key: "sk-test", provider: "openai"}
      ]

      assert {:ok, response} = OpenAI.generate_sql(opts)
      assert response.content == "SELECT COUNT(*) FROM users WHERE status = 'active'"
    end
  end
end
