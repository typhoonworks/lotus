defmodule Lotus.AI.ProviderRegistryTest do
  use Lotus.Case, async: true

  alias Lotus.AI.ProviderRegistry

  describe "get_provider/1" do
    test "returns OpenAI provider module" do
      assert {:ok, Lotus.AI.Providers.OpenAI} = ProviderRegistry.get_provider("openai")
    end

    test "returns Anthropic provider module" do
      assert {:ok, Lotus.AI.Providers.Anthropic} = ProviderRegistry.get_provider("anthropic")
    end

    test "returns Gemini provider module" do
      assert {:ok, Lotus.AI.Providers.Gemini} = ProviderRegistry.get_provider("gemini")
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = ProviderRegistry.get_provider("unknown")
    end

    test "returns error for nil provider" do
      assert {:error, :unknown_provider} = ProviderRegistry.get_provider(nil)
    end

    test "returns error for empty string" do
      assert {:error, :unknown_provider} = ProviderRegistry.get_provider("")
    end
  end

  describe "list_providers/0" do
    test "returns all supported providers in alphabetical order" do
      assert ProviderRegistry.list_providers() == ["anthropic", "gemini", "openai"]
    end
  end

  describe "supported?/1" do
    test "returns true for supported providers" do
      assert ProviderRegistry.supported?("openai")
      assert ProviderRegistry.supported?("anthropic")
      assert ProviderRegistry.supported?("gemini")
    end

    test "returns false for unsupported providers" do
      refute ProviderRegistry.supported?("unknown")
      refute ProviderRegistry.supported?("gpt4")
      refute ProviderRegistry.supported?("")
      refute ProviderRegistry.supported?(nil)
    end
  end
end
