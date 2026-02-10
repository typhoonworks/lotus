defmodule Lotus.AI.Providers.GeminiTest do
  use Lotus.AICase, async: true

  alias Lotus.AI.Providers.Gemini

  describe "default_model/0" do
    test "returns gemini-2.0-flash-exp" do
      assert Gemini.default_model() == "gemini-2.0-flash-exp"
    end
  end

  describe "validate_key/1" do
    test "accepts valid non-empty string" do
      config = %{api_key: "AIzaSyTest123"}

      assert :ok = Gemini.validate_key(config)
    end

    test "accepts any non-empty string" do
      config = %{api_key: "anything-non-empty"}

      assert :ok = Gemini.validate_key(config)
    end

    test "rejects empty string" do
      config = %{api_key: ""}

      assert {:error, _message} = Gemini.validate_key(config)
    end
  end

  describe "generate_sql/1" do
    setup do
      setup_mocks()

      stub(Lotus.Sources, :source_type, fn _ -> :postgres end)
      stub(Lotus.Schema, :list_tables, fn _ -> {:ok, table_list()} end)

      :ok
    end

    test "generates SQL successfully with Gemini response format" do
      # Gemini uses promptTokenCount/candidatesTokenCount/totalTokenCount
      mock_complex_sql()

      opts = [
        prompt: "Top products by revenue",
        data_source: "postgres",
        config: %{api_key: "AIzaSyTest", provider: "gemini"}
      ]

      assert {:ok, response} = Gemini.generate_sql(opts)

      assert response.content =~ "SELECT"
      assert response.content =~ "JOIN"
      assert response.model == "gemini-2.0-flash-exp"
      # Should correctly map Gemini's token format
      assert response.usage.prompt_tokens == 200
      assert response.usage.completion_tokens == 80
      assert response.usage.total_tokens == 280
    end

    test "uses configured model override" do
      mock_with_assertion(fn chain ->
        assert chain.llm.model == "gemini-pro"
      end)

      opts = [
        prompt: "Test",
        data_source: "postgres",
        config: %{api_key: "AIzaSyTest", provider: "gemini", model: "gemini-pro"}
      ]

      assert {:ok, _response} = Gemini.generate_sql(opts)
    end

    test "returns error when LLM refuses" do
      mock_unable_to_generate()

      opts = [
        prompt: "Non-SQL question",
        data_source: "postgres",
        config: %{api_key: "AIzaSyTest", provider: "gemini"}
      ]

      assert {:error, {:unable_to_generate, _reason}} = Gemini.generate_sql(opts)
    end
  end
end
