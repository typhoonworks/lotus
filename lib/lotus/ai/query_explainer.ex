defmodule Lotus.AI.QueryExplainer do
  @moduledoc """
  Generates AI-powered plain-language explanations for SQL queries.

  Supports explaining a full query or a selected fragment in context
  of the full query.
  """

  require Logger

  alias Lotus.AI.Prompts.Explanation
  alias Lotus.AI.Tools.SchemaTools

  @max_tool_iterations 10

  @doc """
  Generate a plain-language explanation for a SQL query or fragment.

  ## Options

  - `:sql` (required) - The full SQL query
  - `:fragment` (optional) - A selected portion of the query to explain
  - `:data_source` (required) - Name of the data source
  - `:api_key` (required) - API key for the LLM provider
  - `:temperature` (optional) - LLM temperature (default: `0.2`)

  ## Returns

  - `{:ok, result}` - Map with `:explanation`, `:model`, and `:usage`
  - `{:error, term}` - Error tuple
  """
  @spec explain_query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def explain_query(model_string, opts) do
    data_source = Keyword.fetch!(opts, :data_source)
    sql = Keyword.fetch!(opts, :sql)
    fragment = Keyword.get(opts, :fragment)
    api_key = Keyword.fetch!(opts, :api_key)
    temperature = Keyword.get(opts, :temperature, 0.2)

    database_type = Lotus.Sources.source_type(data_source)

    system_prompt = Explanation.system_prompt(database_type)

    user_prompt =
      if fragment do
        Explanation.fragment_prompt(fragment, sql)
      else
        Explanation.user_prompt(sql)
      end

    tools = build_tools(data_source)
    messages = build_messages(system_prompt, user_prompt)
    context = ReqLLM.Context.new(messages)

    run_with_tools(model_string, context, tools, api_key, temperature)
    |> handle_response(model_string)
  end

  defp build_tools(data_source) do
    [
      build_get_table_schema_tool(data_source)
    ]
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

  defp build_messages(system_prompt, user_prompt) do
    [
      ReqLLM.Context.system(system_prompt),
      ReqLLM.Context.user(user_prompt)
    ]
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

          %{type: :tool_calls} ->
            Logger.warning(
              "Query explainer reached max tool iterations (#{@max_tool_iterations})"
            )

            {:ok, response}

          _ ->
            {:ok, response}
        end

      {:error, _} = error ->
        error
    end
  end

  defp handle_response({:ok, response}, model_string) do
    explanation = ReqLLM.Response.text(response)
    usage = ReqLLM.Response.usage(response) || %{}

    {:ok,
     %{
       explanation: explanation,
       model: model_string,
       usage: %{
         prompt_tokens: usage[:input_tokens] || 0,
         completion_tokens: usage[:output_tokens] || 0,
         total_tokens: usage[:total_tokens] || 0
       }
     }}
  end

  defp handle_response({:error, error}, _model_string), do: {:error, error}
end
