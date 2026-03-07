defmodule Lotus.AI.QueryOptimizer do
  @moduledoc """
  Generates AI-powered optimization suggestions for SQL queries.

  Analyzes a query's execution plan and structure to suggest index additions,
  query rewrites, or structural improvements.
  """

  require Logger

  alias Lotus.AI.Prompts.Optimization
  alias Lotus.AI.Tools.SchemaTools

  @max_tool_iterations 10

  @doc """
  Generate optimization suggestions for a SQL query.

  Runs EXPLAIN on the query to get the execution plan, then sends both
  the SQL and plan to the AI for analysis.

  ## Options

  - `:sql` (required) - The SQL query to optimize
  - `:data_source` (required) - Name of the data source
  - `:api_key` (required) - API key for the LLM provider
  - `:params` (optional) - Query parameters (default: `[]`)
  - `:search_path` (optional) - PostgreSQL search path
  - `:temperature` (optional) - LLM temperature (default: `0.1`)

  ## Returns

  - `{:ok, result}` - Map with `:suggestions`, `:model`, and `:usage`
  - `{:error, term}` - Error tuple
  """
  @spec suggest_optimizations(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def suggest_optimizations(model_string, opts) do
    data_source = Keyword.fetch!(opts, :data_source)
    sql = Keyword.fetch!(opts, :sql)
    api_key = Keyword.fetch!(opts, :api_key)
    params = Keyword.get(opts, :params, [])
    search_path = Keyword.get(opts, :search_path)
    temperature = Keyword.get(opts, :temperature, 0.1)

    database_type = Lotus.Sources.source_type(data_source)
    repo = Lotus.Config.get_data_repo!(data_source)

    execution_plan = get_execution_plan(repo, sql, params, search_path: search_path)

    system_prompt = Optimization.system_prompt(database_type)
    user_prompt = Optimization.user_prompt(sql, execution_plan)

    tools = build_tools(data_source)
    messages = build_messages(system_prompt, user_prompt)
    context = ReqLLM.Context.new(messages)

    run_with_tools(model_string, context, tools, api_key, temperature)
    |> handle_response(model_string)
  end

  defp get_execution_plan(repo, sql, params, opts) do
    explainable_sql = prepare_sql_for_explain(sql)

    case Lotus.Source.explain_plan(repo, explainable_sql, params, opts) do
      {:ok, plan} -> plan
      {:error, _} -> nil
    end
  end

  # Strips Lotus-specific syntax so the SQL is valid for EXPLAIN:
  # - Removes [[ ]] brackets (keeps inner content so all clauses are visible)
  # - Replaces {{variable}} placeholders with NULL
  # Note: nested [[ ]] is not part of Lotus syntax and is not supported.
  defp prepare_sql_for_explain(sql) do
    sql
    |> String.replace(~r/\[\[(.*?)\]\]/s, "\\1")
    |> String.replace(~r/\{\{[A-Za-z_][A-Za-z0-9_]*\}\}/, "NULL")
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
              "Query optimizer reached max tool iterations (#{@max_tool_iterations})"
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
    content = ReqLLM.Response.text(response)
    suggestions = Optimization.parse_suggestions(content)
    usage = ReqLLM.Response.usage(response) || %{}

    {:ok,
     %{
       suggestions: suggestions,
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
