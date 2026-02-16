defmodule Lotus.AITest do
  use Lotus.AICase, async: true

  alias Lotus.AI

  describe "enabled?/0" do
    test "returns false when AI not configured" do
      refute AI.enabled?()
    end

    test "returns false when AI disabled" do
      set_ai_config(enabled: false)

      refute AI.enabled?()
    end

    test "returns false when API key missing" do
      set_ai_config(enabled: true, provider: "openai")

      refute AI.enabled?()
    end

    test "returns true when properly configured" do
      set_ai_config(enabled: true, provider: "openai", api_key: "sk-test123")

      assert AI.enabled?()
    end
  end

  describe "provider/0" do
    test "returns error when not configured" do
      assert {:error, :not_configured} = AI.provider()
    end

    test "returns configured provider" do
      set_ai_config(enabled: true, provider: "anthropic", api_key: "sk-ant-test")

      assert {:ok, "anthropic"} = AI.provider()
    end

    test "defaults to openai when provider not specified" do
      set_ai_config(enabled: true, api_key: "sk-test")

      assert {:ok, "openai"} = AI.provider()
    end
  end

  describe "model/0" do
    test "returns error when not configured" do
      assert {:error, :not_configured} = AI.model()
    end

    test "returns provider default when model not specified" do
      set_ai_config(enabled: true, provider: "openai", api_key: "sk-test")

      assert {:ok, "gpt-4o"} = AI.model()
    end

    test "returns configured model override" do
      set_ai_config(enabled: true, provider: "openai", api_key: "sk-test", model: "gpt-3.5-turbo")

      assert {:ok, "gpt-3.5-turbo"} = AI.model()
    end
  end

  describe "generate_query/1" do
    setup do
      setup_mocks()

      # Mock schema introspection
      stub(Lotus.Sources, :source_type, fn _ -> :postgres end)
      stub(Lotus.Schema, :list_tables, fn _ -> {:ok, table_list()} end)

      set_ai_config(enabled: true, provider: "openai", api_key: "sk-test")

      :ok
    end

    test "generates SQL successfully" do
      mock_successful_generation()

      assert {:ok, result} =
               AI.generate_query(
                 prompt: "Show active users from last 30 days",
                 data_source: "postgres"
               )

      assert result.sql =~ "SELECT * FROM users"
      assert result.sql =~ "created_at >= NOW()"
      assert result.variables == []
      assert result.provider == "openai"
      assert result.model == "gpt-4o"
      assert result.usage.total_tokens == 200
    end

    test "returns variables when LLM generates them" do
      mock_sql_with_variables()

      assert {:ok, result} =
               AI.generate_query(
                 prompt: "Show orders with a status dropdown",
                 data_source: "postgres"
               )

      assert result.sql =~ "SELECT * FROM orders"
      assert length(result.variables) == 1
      assert hd(result.variables)["name"] == "status"
    end

    test "handles plain SQL without markdown" do
      mock_plain_sql()

      assert {:ok, result} =
               AI.generate_query(
                 prompt: "Count active users",
                 data_source: "postgres"
               )

      assert result.sql == "SELECT COUNT(*) FROM users WHERE status = 'active'"
    end

    test "handles complex SQL with JOINs" do
      mock_complex_sql()

      assert {:ok, result} =
               AI.generate_query(
                 prompt: "Top products by revenue",
                 data_source: "postgres"
               )

      assert result.sql =~ "SELECT"
      assert result.sql =~ "JOIN"
      assert result.sql =~ "GROUP BY"
    end

    test "returns structured error when AI not configured" do
      Application.delete_env(:lotus, :ai)

      assert {:error, :not_configured} =
               AI.generate_query(
                 prompt: "test",
                 data_source: "postgres"
               )
    end

    test "returns structured error when API key missing" do
      set_ai_config(enabled: true, provider: "openai")

      assert {:error, :api_key_not_configured} =
               AI.generate_query(
                 prompt: "test",
                 data_source: "postgres"
               )
    end

    test "returns structured error when provider unknown" do
      set_ai_config(enabled: true, provider: "unknown", api_key: "test")

      assert {:error, :unknown_provider} =
               AI.generate_query(
                 prompt: "test",
                 data_source: "postgres"
               )
    end

    test "returns structured error when LLM refuses to generate" do
      mock_unable_to_generate()

      assert {:error, {:unable_to_generate, reason}} =
               AI.generate_query(
                 prompt: "What's the weather?",
                 data_source: "postgres"
               )

      assert reason == "This is a weather question, not a database query"
    end

    test "returns error when API fails" do
      mock_api_error("Rate limit exceeded")

      assert {:error, "Rate limit exceeded"} =
               AI.generate_query(
                 prompt: "test",
                 data_source: "postgres"
               )
    end

    test "returns error when request times out" do
      mock_timeout()

      assert {:error, :timeout} =
               AI.generate_query(
                 prompt: "test",
                 data_source: "postgres"
               )
    end

    test "resolves {:system, env_var} API key" do
      System.put_env("TEST_AI_KEY", "sk-from-env")
      set_ai_config(enabled: true, provider: "openai", api_key: {:system, "TEST_AI_KEY"})

      mock_successful_generation()

      assert {:ok, _result} =
               AI.generate_query(
                 prompt: "test",
                 data_source: "postgres"
               )

      System.delete_env("TEST_AI_KEY")
    end
  end

  describe "generate_query_with_context/1" do
    setup do
      setup_mocks()

      stub(Lotus.Sources, :source_type, fn _ -> :postgres end)
      stub(Lotus.Schema, :list_tables, fn _ -> {:ok, table_list()} end)

      set_ai_config(enabled: true, provider: "openai", api_key: "sk-test")

      :ok
    end

    test "returns variables in result map" do
      mock_sql_with_variables()

      assert {:ok, result} =
               AI.generate_query_with_context(
                 prompt: "Show orders with a status dropdown",
                 data_source: "postgres"
               )

      assert result.sql =~ "SELECT * FROM orders"
      assert length(result.variables) == 1
      assert hd(result.variables)["name"] == "status"
    end

    test "returns empty variables for SQL-only response" do
      mock_successful_generation()

      assert {:ok, result} =
               AI.generate_query_with_context(
                 prompt: "Show active users",
                 data_source: "postgres"
               )

      assert result.variables == []
    end
  end

  # Helper functions

  defp set_ai_config(opts) do
    Application.put_env(:lotus, :ai, opts)

    on_exit(fn ->
      Application.delete_env(:lotus, :ai)
    end)
  end
end
