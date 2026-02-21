defmodule Lotus.AI.Provider do
  @moduledoc """
  Behaviour for LLM provider adapters with tool/function calling support.

  Providers must implement SQL generation using tool-based schema querying
  for scalability with large databases.

  ## Callbacks

  - `generate_sql/1` - Generate SQL from natural language prompt
  - `validate_key/1` - Validate API key configuration
  - `default_model/0` - Return the provider's default/recommended model
  """

  @type config :: %{
          api_key: String.t(),
          provider: String.t(),
          model: String.t() | nil
        }

  @type generate_opts :: [
          prompt: String.t(),
          data_source: String.t(),
          config: config(),
          read_only: boolean()
        ]

  @type response :: %{
          content: String.t(),
          model: String.t(),
          variables: [map()],
          usage: %{
            prompt_tokens: non_neg_integer(),
            completion_tokens: non_neg_integer(),
            total_tokens: non_neg_integer()
          }
        }

  @doc """
  Generate SQL query from natural language prompt.

  Providers should use tool calling to query schema on-demand rather than
  including full schema in initial prompt for scalability.

  ## Options

  - `:prompt` - Natural language query description
  - `:data_source` - Name of the data source to query against
  - `:config` - Provider configuration including API key and model
  - `:read_only` - When `true` (default), instructs the LLM to only generate read-only queries

  ## Returns

  - `{:ok, response}` - Successfully generated SQL
  - `{:error, {:unable_to_generate, reason}}` - LLM determined question is not SQL-related
  - `{:error, term}` - Other errors (API failures, network issues, etc.)
  """
  @callback generate_sql(generate_opts()) :: {:ok, response()} | {:error, term()}

  @doc """
  Validate API key configuration.

  Returns `:ok` if the key is valid, `{:error, reason}` otherwise.
  """
  @callback validate_key(config()) :: :ok | {:error, term()}

  @doc """
  Return the provider's default/recommended model name.
  """
  @callback default_model() :: String.t()
end
