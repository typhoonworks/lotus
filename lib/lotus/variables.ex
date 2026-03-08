defmodule Lotus.Variables do
  @moduledoc """
  Utilities for Lotus `{{variable}}` template syntax.

  Variables use the `{{name}}` placeholder format and can appear in SQL
  queries, templates, or any other Lotus content type.
  """

  @variable_regex ~r/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/

  @doc """
  Returns the compiled regex for matching `{{variable}}` placeholders.

  Captures the variable name (without braces) in group 1.

  ## Examples

      iex> Regex.scan(Lotus.Variables.regex(), "WHERE id = {{user_id}}")
      [["{{user_id}}", "user_id"]]
  """
  @spec regex() :: Regex.t()
  def regex, do: @variable_regex

  @doc """
  Extracts variable names from a string containing `{{variable}}` placeholders.

  Returns names in the order they appear, with duplicates preserved.

  ## Examples

      iex> Lotus.Variables.extract_names("WHERE id = {{user_id}} AND status = {{status}}")
      ["user_id", "status"]

      iex> Lotus.Variables.extract_names("no variables here")
      []
  """
  @spec extract_names(String.t()) :: [String.t()]
  def extract_names(content) do
    Regex.scan(@variable_regex, content)
    |> Enum.map(fn [_, name] -> name end)
  end

  @doc """
  Replaces all `{{variable}}` placeholders with the given replacement value.

  Useful for neutralizing variables before validation (e.g. replacing with
  `"NULL"` for SQL syntax checking) or for any context where placeholders
  need to be substituted with a static value.

  ## Examples

      iex> Lotus.Variables.neutralize("SELECT * FROM users WHERE id = {{user_id}}", "NULL")
      "SELECT * FROM users WHERE id = NULL"

      iex> Lotus.Variables.neutralize("Hello {{name}}", "")
      "Hello "
  """
  @spec neutralize(String.t(), String.t()) :: String.t()
  def neutralize(content, replacement) do
    Regex.replace(@variable_regex, content, replacement)
  end
end
