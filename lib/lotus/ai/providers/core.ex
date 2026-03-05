defmodule Lotus.AI.Providers.Core do
  @moduledoc """
  Shared implementation for LLM provider adapters.

  Contains the common logic for chain building, tool construction,
  message handling, and response extraction used by all providers.
  Providers create their specific chat model struct and delegate here.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.Function
  alias LangChain.Message
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
  Generate SQL using the given chat model struct.

  Builds a LangChain chain with schema tools, runs it until complete,
  and extracts the SQL and variables from the response.
  """
  @spec generate_sql(struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_sql(chat_model, opts) do
    data_source = Keyword.fetch!(opts, :data_source)
    prompt = Keyword.fetch!(opts, :prompt)
    conversation = Keyword.get(opts, :conversation)
    query_context = Keyword.get(opts, :query_context)
    read_only = Keyword.get(opts, :read_only, true)

    build_chain(chat_model, prompt, data_source, conversation, query_context, read_only)
    |> run_until_complete()
    |> handle_response()
  end

  defp build_chain(chat_model, prompt, data_source, conversation, query_context, read_only) do
    database_type = Lotus.Sources.source_type(data_source)

    {:ok, all_schemas} = Lotus.Schema.list_schemas(data_source)
    {:ok, tables} = Lotus.Schema.list_tables(data_source, schemas: all_schemas)
    table_names = extract_table_names(tables)

    system_prompt = SQLGeneration.system_prompt(database_type, table_names, read_only: read_only)

    tools = build_tools(data_source)
    messages = build_messages(conversation, prompt, system_prompt, query_context)

    LLMChain.new!(%{llm: chat_model, tools: tools})
    |> LLMChain.add_messages(messages)
  end

  defp run_until_complete(chain, iteration \\ 1) do
    case LLMChain.run(chain) do
      {:ok, updated_chain} ->
        if updated_chain.needs_response and iteration < @max_tool_iterations do
          chain_with_tool_results = LLMChain.execute_tool_calls(updated_chain)
          run_until_complete(chain_with_tool_results, iteration + 1)
        else
          {:ok, updated_chain}
        end

      {:error, _chain, _error} = error ->
        error
    end
  end

  defp handle_response({:ok, updated_chain}) do
    content = extract_content(updated_chain.last_message.content)

    case SQLGeneration.extract_response(content) do
      {:ok, %{sql: sql, variables: variables}} ->
        {:ok, build_success_response(updated_chain, sql, variables)}

      {:error, {:unable_to_generate, reason}} ->
        {:error, {:unable_to_generate, reason}}
    end
  end

  defp handle_response({:error, _chain, error}), do: {:error, error}

  defp extract_content(text) when is_binary(text), do: text

  defp extract_content([%{type: :text, content: text} | _]), do: text

  defp extract_content(parts) when is_list(parts) do
    parts
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join("\n", & &1.content)
  end

  defp extract_content(nil), do: nil

  defp build_success_response(chain, sql, variables) do
    usage = chain.last_message.metadata[:usage]

    %{
      content: sql,
      model: chain.llm.model,
      variables: variables,
      usage: %{
        prompt_tokens: usage.input || 0,
        completion_tokens: usage.output || 0,
        total_tokens: (usage.input || 0) + (usage.output || 0)
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

    %Function{
      name: metadata.name,
      description: metadata.description,
      parameters_schema: %{
        type: "object",
        properties: metadata.parameters,
        required: []
      },
      function: fn _args, _context ->
        case SchemaTools.list_schemas(data_source) do
          {:ok, json} -> json
          {:error, reason} -> Lotus.JSON.encode!(%{error: inspect(reason)})
        end
      end
    }
  end

  defp build_list_tables_tool(data_source) do
    metadata = SchemaTools.list_tables_metadata()

    %Function{
      name: metadata.name,
      description: metadata.description,
      parameters_schema: %{
        type: "object",
        properties: metadata.parameters,
        required: []
      },
      function: fn _args, _context ->
        case SchemaTools.list_tables(data_source) do
          {:ok, json} -> json
          {:error, reason} -> Lotus.JSON.encode!(%{error: inspect(reason)})
        end
      end
    }
  end

  defp build_get_table_schema_tool(data_source) do
    metadata = SchemaTools.get_table_schema_metadata()

    %Function{
      name: metadata.name,
      description: metadata.description,
      parameters_schema: %{
        type: "object",
        properties: %{
          table_name: %{
            type: "string",
            description: metadata.parameters.table_name.description
          }
        },
        required: ["table_name"]
      },
      function: fn %{"table_name" => table}, _context ->
        case SchemaTools.get_table_schema(data_source, table) do
          {:ok, json} -> json
          {:error, reason} -> Lotus.JSON.encode!(%{error: inspect(reason)})
        end
      end
    }
  end

  defp build_get_column_values_tool(data_source) do
    metadata = SchemaTools.get_column_values_metadata()

    %Function{
      name: metadata.name,
      description: metadata.description,
      parameters_schema: %{
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
      function: fn %{"table_name" => table, "column_name" => column}, _context ->
        case SchemaTools.get_column_values(data_source, table, column) do
          {:ok, json} -> json
          {:error, reason} -> Lotus.JSON.encode!(%{error: inspect(reason)})
        end
      end
    }
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
    |> convert_to_langchain_messages()
  end

  defp build_conversation_messages(conversation, prompt, system_prompt, query_context) do
    conversation
    |> Conversation.build_context_messages(system_prompt, query_context)
    |> convert_to_langchain_messages()
    |> maybe_add_current_prompt(conversation, prompt)
  end

  defp convert_to_langchain_messages(messages) do
    Enum.map(messages, fn msg ->
      case msg.role do
        :system -> Message.new_system!(msg.content)
        :user -> Message.new_user!(msg.content)
        :assistant -> Message.new_assistant!(msg.content)
      end
    end)
  end

  defp maybe_add_current_prompt(messages, conversation, prompt) do
    last_user_msg = find_last_user_message(conversation)

    if last_user_msg && last_user_msg.content == prompt do
      messages
    else
      messages ++ [Message.new_user!(prompt)]
    end
  end

  defp find_last_user_message(conversation) do
    conversation.messages
    |> Enum.reverse()
    |> Enum.find(&(&1.role == :user))
  end
end
