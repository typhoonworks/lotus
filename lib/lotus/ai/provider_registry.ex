defmodule Lotus.AI.ProviderRegistry do
  @moduledoc """
  Registry for built-in LLM providers.

  Free version supports: OpenAI, Anthropic, Gemini
  Pro version: Custom providers, per-user provider selection
  """

  @providers %{
    "openai" => Lotus.AI.Providers.OpenAI,
    "anthropic" => Lotus.AI.Providers.Anthropic,
    "gemini" => Lotus.AI.Providers.Gemini
  }

  @doc """
  Get provider module for a provider name.

  Returns `{:ok, module}` if the provider exists, `{:error, :unknown_provider}` otherwise.

  ## Examples

      iex> Lotus.AI.ProviderRegistry.get_provider("openai")
      {:ok, Lotus.AI.Providers.OpenAI}

      iex> Lotus.AI.ProviderRegistry.get_provider("unknown")
      {:error, :unknown_provider}
  """
  @spec get_provider(String.t()) :: {:ok, module()} | {:error, :unknown_provider}
  def get_provider(provider_name) when provider_name in ["openai", "anthropic", "gemini"] do
    {:ok, Map.fetch!(@providers, provider_name)}
  end

  def get_provider(_), do: {:error, :unknown_provider}

  @doc """
  List supported provider names.

  ## Examples

      iex> Lotus.AI.ProviderRegistry.list_providers()
      ["anthropic", "gemini", "openai"]
  """
  @spec list_providers() :: [String.t()]
  def list_providers, do: Map.keys(@providers) |> Enum.sort()

  @doc """
  Check if a provider name is supported.

  ## Examples

      iex> Lotus.AI.ProviderRegistry.supported?("openai")
      true

      iex> Lotus.AI.ProviderRegistry.supported?("unknown")
      false
  """
  @spec supported?(String.t()) :: boolean()
  def supported?(provider_name), do: Map.has_key?(@providers, provider_name)
end
