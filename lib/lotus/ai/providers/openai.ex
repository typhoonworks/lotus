defmodule Lotus.AI.Providers.OpenAI do
  @moduledoc """
  OpenAI provider implementation for Lotus AI.

  Supports GPT-4 and GPT-3.5 models with tool-based schema querying.
  """

  @behaviour Lotus.AI.Provider

  alias LangChain.ChatModels.ChatOpenAI
  alias Lotus.AI.Providers.Core

  @impl true
  def default_model, do: "gpt-4o"

  @impl true
  def validate_key(config), do: Core.validate_key(config)

  @impl true
  def generate_sql(opts) do
    config = Keyword.fetch!(opts, :config)

    chat_model = %ChatOpenAI{
      model: config[:model] || default_model(),
      api_key: config.api_key,
      temperature: 0.1
    }

    Core.generate_sql(chat_model, opts)
  end
end
