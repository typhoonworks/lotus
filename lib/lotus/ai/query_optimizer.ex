defmodule Lotus.AI.QueryOptimizer do
  @moduledoc """
  Generates AI-powered optimization suggestions for SQL queries.

  Analyzes a query's execution plan and structure to suggest index additions,
  query rewrites, or structural improvements.
  """

  alias Lotus.AI.Actions
  alias Lotus.AI.Prompts.Optimization
  alias Lotus.AI.Tool

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

    Tool.run(model_string, context, tools, api_key: api_key, temperature: temperature)
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
      Tool.from_action(Actions.GetTableSchema, bind: %{data_source: data_source})
    ]
  end

  defp build_messages(system_prompt, user_prompt) do
    [
      ReqLLM.Context.system(system_prompt),
      ReqLLM.Context.user(user_prompt)
    ]
  end

  defp handle_response({:ok, response}, model_string) do
    content = ReqLLM.Response.text(response)

    {:ok,
     %{
       suggestions: Optimization.parse_suggestions(content),
       model: model_string,
       usage: Tool.normalize_usage(ReqLLM.Response.usage(response))
     }}
  end

  defp handle_response({:error, error}, _model_string), do: {:error, error}
end
