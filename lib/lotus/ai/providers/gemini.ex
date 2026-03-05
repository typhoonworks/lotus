defmodule Lotus.AI.Providers.Gemini do
  @moduledoc """
  Google Gemini provider implementation for Lotus AI.

  Supports Gemini models with tool-based schema querying.
  """

  @behaviour Lotus.AI.Provider

  alias LangChain.ChatModels.ChatGoogleAI
  alias Lotus.AI.Providers.Core

  @impl true
  def default_model, do: "gemini-2.0-flash-exp"

  @impl true
  def validate_key(config), do: Core.validate_key(config)

  @impl true
  def generate_sql(opts) do
    config = Keyword.fetch!(opts, :config)

    chat_model = %ChatGoogleAI{
      model: config[:model] || default_model(),
      api_key: config.api_key,
      temperature: 0.1
    }

    Core.generate_sql(chat_model, opts)
  end
end
