defmodule Lotus.SQL.Validator do
  @moduledoc """
  Validates SQL syntax by preparing it against the database without executing.

  Uses EXPLAIN to parse the query server-side. Before validation, `{{var}}`
  placeholders are replaced with NULL and `[[...]]` optional brackets are
  stripped so the raw template can be checked.
  """

  alias Lotus.SQL.OptionalClause
  alias Lotus.Variables

  @doc """
  Validates SQL syntax against the given data source.

  Neutralizes Lotus template syntax (`{{var}}` → `NULL`, `[[...]]` → inner
  content) and runs EXPLAIN to check whether the database can parse the
  statement.

  Returns `:ok` if the SQL is valid, or `{:error, reason}` with the
  database error message if it is not.

  ## Examples

      iex> Lotus.SQL.Validator.validate("SELECT 1", "postgres")
      :ok

      iex> Lotus.SQL.Validator.validate("NOT VALID SQL", "postgres")
      {:error, "SQL syntax error: ..."}
  """
  @spec validate(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate(sql, data_source) do
    neutralized =
      sql
      |> OptionalClause.strip_brackets()
      |> Variables.neutralize("NULL")

    repo = Lotus.Config.get_data_source!(data_source)

    case Lotus.Source.explain_plan(repo, neutralized) do
      {:ok, _plan} -> :ok
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
