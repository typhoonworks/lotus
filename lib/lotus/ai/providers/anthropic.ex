defmodule Lotus.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic (Claude) provider implementation for Lotus AI.

  Supports Claude models with tool-based schema querying.
  """

  @behaviour Lotus.AI.Provider

  alias LangChain.ChatModels.ChatAnthropic
  alias Lotus.AI.Providers.Core

  @impl true
  def default_model, do: "claude-opus-4"

  @impl true
  def validate_key(config), do: Core.validate_key(config)

  @impl true
  def generate_sql(opts) do
    config = Keyword.fetch!(opts, :config)

    chat_model = %ChatAnthropic{
      model: config[:model] || default_model(),
      api_key: config.api_key,
      temperature: 0.1
    }

    Core.generate_sql(chat_model, opts)
  end
end
