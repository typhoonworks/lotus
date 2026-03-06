defmodule Lotus.AI.SQLGenerator do
  @moduledoc """
  Generates SQL from natural language using ReqLLM.

  Handles tool building, message handling, and response extraction.
  Any provider supported by ReqLLM can be used by passing a model
  string like `"openai:gpt-4o"` or `"anthropic:claude-opus-4"`.
  """

  alias Lotus.AI.Conversation
  alias Lotus.AI.Prompts.SQLGeneration
  alias Lotus.AI.Tools.SchemaTools

  @max_tool_iterations 10

  @doc """
  Validate that a config contains a non-empty API key string.
  """
  @spec validate_key(map()) :: :ok | {:error, String.t()}
  def validate_key(config) do
    if is_binary(config.api_key) and String.length(config.api_key) > 0 do
      :ok
    else
      {:error, "API key must be a non-empty string"}
    end
  end

  @doc """
  Generate SQL using the given model string and options.

  The model string should be in ReqLLM format, e.g. `"openai:gpt-4o"`,
  `"anthropic:claude-opus-4"`, `"google:gemini-2.0-flash"`.

  ## Options

  - `:prompt` (required) - Natural language query
  - `:data_source` (required) - Name of the data source
  - `:api_key` (required) - API key for the provider
  - `:conversation` - Conversation struct for multi-turn
  - `:query_context` - Additional context for the query
  - `:read_only` - Whether to restrict to read-only SQL (default: true)
  - `:temperature` - LLM temperature (default: 0.1)
  """
  @spec generate_sql(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_sql(model_string, opts) do
    data_source = Keyword.fetch!(opts, :data_source)
    prompt = Keyword.fetch!(opts, :prompt)
    conversation = Keyword.get(opts, :conversation)
    query_context = Keyword.get(opts, :query_context)
    read_only = Keyword.get(opts, :read_only, true)
    api_key = Keyword.fetch!(opts, :api_key)
    temperature = Keyword.get(opts, :temperature, 0.1)

    database_type = Lotus.Sources.source_type(data_source)

    {:ok, all_schemas} = Lotus.Schema.list_schemas(data_source)
    {:ok, tables} = Lotus.Schema.list_tables(data_source, schemas: all_schemas)
    table_names = extract_table_names(tables)

    system_prompt = SQLGeneration.system_prompt(database_type, table_names, read_only: read_only)

    tools = build_tools(data_source)
    messages = build_messages(conversation, prompt, system_prompt, query_context)
    context = build_context(messages)

    run_with_tools(model_string, context, tools, api_key, temperature)
    |> handle_response(model_string)
  end

  defp run_with_tools(model_string, context, tools, api_key, temperature, iteration \\ 1) do
    messages = ReqLLM.Context.to_list(context)

    case ReqLLM.generate_text(model_string, messages,
           tools: tools,
           api_key: api_key,
           temperature: temperature
         ) do
      {:ok, response} ->
        case ReqLLM.Response.classify(response) do
          %{type: :tool_calls, tool_calls: tool_calls} when iteration < @max_tool_iterations ->
            updated_context =
              ReqLLM.Context.execute_and_append_tools(response.context, tool_calls, tools)

            run_with_tools(
              model_string,
              updated_context,
              tools,
              api_key,
              temperature,
              iteration + 1
            )

          _ ->
            {:ok, response}
        end

      {:error, _} = error ->
        error
    end
  end

  defp handle_response({:ok, response}, model_string) do
    content = ReqLLM.Response.text(response)

    case SQLGeneration.extract_response(content) do
      {:ok, %{sql: sql, variables: variables}} ->
        {:ok, build_success_response(response, model_string, sql, variables)}

      {:error, {:unable_to_generate, reason}} ->
        {:error, {:unable_to_generate, reason}}
    end
  end

  defp handle_response({:error, error}, _model_string), do: {:error, error}

  defp build_success_response(response, model_string, sql, variables) do
    usage = ReqLLM.Response.usage(response) || %{}

    %{
      content: sql,
      model: model_string,
      variables: variables,
      usage: %{
        prompt_tokens: usage[:input_tokens] || 0,
        completion_tokens: usage[:output_tokens] || 0,
        total_tokens: usage[:total_tokens] || 0
      }
    }
  end

  # Tools

  defp build_tools(data_source) do
    [
      build_list_schemas_tool(data_source),
      build_list_tables_tool(data_source),
      build_get_table_schema_tool(data_source),
      build_get_column_values_tool(data_source)
    ]
  end

  defp build_list_schemas_tool(data_source) do
    metadata = SchemaTools.list_schemas_metadata()

    ReqLLM.tool(
      name: metadata.name,
      description: metadata.description,
      parameter_schema: %{
        type: "object",
        properties: metadata.parameters,
        required: []
      },
      callback: fn _args ->
        case SchemaTools.list_schemas(data_source) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:ok, Lotus.JSON.encode!(%{error: inspect(reason)})}
        end
      end
    )
  end

  defp build_list_tables_tool(data_source) do
    metadata = SchemaTools.list_tables_metadata()

    ReqLLM.tool(
      name: metadata.name,
      description: metadata.description,
      parameter_schema: %{
        type: "object",
        properties: metadata.parameters,
        required: []
      },
      callback: fn _args ->
        case SchemaTools.list_tables(data_source) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:ok, Lotus.JSON.encode!(%{error: inspect(reason)})}
        end
      end
    )
  end

  defp build_get_table_schema_tool(data_source) do
    metadata = SchemaTools.get_table_schema_metadata()

    ReqLLM.tool(
      name: metadata.name,
      description: metadata.description,
      parameter_schema: %{
        type: "object",
        properties: %{
          table_name: %{
            type: "string",
            description: metadata.parameters.table_name.description
          }
        },
        required: ["table_name"]
      },
      callback: fn %{"table_name" => table} ->
        case SchemaTools.get_table_schema(data_source, table) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:ok, Lotus.JSON.encode!(%{error: inspect(reason)})}
        end
      end
    )
  end

  defp build_get_column_values_tool(data_source) do
    metadata = SchemaTools.get_column_values_metadata()

    ReqLLM.tool(
      name: metadata.name,
      description: metadata.description,
      parameter_schema: %{
        type: "object",
        properties: %{
          table_name: %{
            type: "string",
            description: metadata.parameters.table_name.description
          },
          column_name: %{
            type: "string",
            description: metadata.parameters.column_name.description
          }
        },
        required: ["table_name", "column_name"]
      },
      callback: fn %{"table_name" => table, "column_name" => column} ->
        case SchemaTools.get_column_values(data_source, table, column) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:ok, Lotus.JSON.encode!(%{error: inspect(reason)})}
        end
      end
    )
  end

  # Messages

  defp extract_table_names(tables) do
    Enum.map(tables, fn
      {schema, table} when not is_nil(schema) -> "#{schema}.#{table}"
      table -> table
    end)
  end

  defp build_messages(conversation, prompt, system_prompt, query_context) do
    if conversation && conversation.messages != [] do
      build_conversation_messages(conversation, prompt, system_prompt, query_context)
    else
      build_single_turn_messages(prompt, system_prompt, query_context)
    end
  end

  defp build_single_turn_messages(prompt, system_prompt, query_context) do
    Conversation.new()
    |> Conversation.add_user_message(prompt)
    |> Conversation.build_context_messages(system_prompt, query_context)
    |> convert_to_req_llm_messages()
  end

  defp build_conversation_messages(conversation, prompt, system_prompt, query_context) do
    conversation
    |> Conversation.build_context_messages(system_prompt, query_context)
    |> convert_to_req_llm_messages()
    |> maybe_add_current_prompt(conversation, prompt)
  end

  defp convert_to_req_llm_messages(messages) do
    Enum.map(messages, fn msg ->
      case msg.role do
        :system -> ReqLLM.Context.system(msg.content)
        :user -> ReqLLM.Context.user(msg.content)
        :assistant -> ReqLLM.Context.assistant(msg.content)
      end
    end)
  end

  defp build_context(messages) do
    ReqLLM.Context.new(messages)
  end

  defp maybe_add_current_prompt(messages, conversation, prompt) do
    last_user_msg = find_last_user_message(conversation)

    if last_user_msg && last_user_msg.content == prompt do
      messages
    else
      messages ++ [ReqLLM.Context.user(prompt)]
    end
  end

  defp find_last_user_message(conversation) do
    conversation.messages
    |> Enum.reverse()
    |> Enum.find(&(&1.role == :user))
  end
end
