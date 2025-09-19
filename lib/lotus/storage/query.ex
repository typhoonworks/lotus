defmodule Lotus.Storage.Query do
  @moduledoc """
  Represents a saved Lotus query.

  Queries can be stored, updated, listed, and executed by the host app.
  Supports `{{var}}` placeholders in the SQL `statement` for value substitution
  only. Variables are bound at runtime using configured variables and are only
  safe for SQL values (WHERE clauses, ORDER BY values, etc.), never for
  identifiers like table names, column names, or schema names.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Lotus.Config
  alias Lotus.Sources
  alias Lotus.SQL.Transformer
  alias Lotus.Storage.QueryVariable

  @type t :: %__MODULE__{
          id: term(),
          name: String.t(),
          description: String.t() | nil,
          statement: String.t(),
          variables: [QueryVariable.t()],
          data_repo: String.t() | nil,
          search_path: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  json_encoder = Lotus.JSON.encoder()

  @derive {json_encoder,
           only: [
             :id,
             :name,
             :description,
             :statement,
             :variables,
             :data_repo,
             :search_path,
             :inserted_at,
             :updated_at
           ]}

  schema "lotus_queries" do
    field(:name, :string)
    field(:description, :string)
    field(:statement, :string)
    field(:data_repo, :string)
    field(:search_path, :string)

    embeds_many(:variables, QueryVariable, on_replace: :delete)

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(name statement)a
  @permitted ~w(name description statement data_repo search_path)a

  def new(attrs), do: changeset(%__MODULE__{}, attrs)
  def update(query, attrs), do: changeset(query, attrs)

  def changeset(query, attrs) do
    query
    |> cast(attrs, @permitted)
    |> cast_embed(:variables, with: &QueryVariable.changeset/2)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_statement()
    |> validate_data_repo()
    |> validate_search_path()
    |> maybe_add_unique_constraint()
  end

  @spec to_sql_params(t(), map()) :: {String.t(), [term()]}
  def to_sql_params(%__MODULE__{statement: sql, variables: vars} = q, supplied_vars \\ %{}) do
    source_type = get_source_type(q.data_repo)
    transformed_sql = Transformer.transform(sql, source_type)

    regex = ~r/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/

    vars_in_order =
      Regex.scan(regex, transformed_sql)
      |> Enum.map(fn [_, var] -> var end)

    Enum.reduce(Enum.with_index(vars_in_order, 1), {transformed_sql, []}, fn {var, idx},
                                                                             {acc_sql, acc_params} ->
      meta = Enum.find(vars, %{}, &(&1.name == var))

      value =
        Map.get(supplied_vars, var) ||
          Map.get(meta, :default) ||
          raise ArgumentError, "Missing required variable: #{var}"

      type = Map.get(meta, :type)
      placeholder = Lotus.Source.param_placeholder(q.data_repo, idx, var, type)

      {
        String.replace(acc_sql, "{{#{var}}}", placeholder, global: false),
        acc_params ++ [cast_value(value, type)]
      }
    end)
  end

  @doc """
  Extracts unique variable names from an SQL statement in order of first occurrence.

  Variables are identified by the `{{variable_name}}` syntax.

  ## Examples

      iex> Lotus.Storage.Query.extract_variables_from_statement("SELECT * FROM users WHERE id = {{user_id}} AND status = {{status}}")
      ["user_id", "status"]

      iex> Lotus.Storage.Query.extract_variables_from_statement("SELECT * FROM users WHERE id = {{user_id}} OR id = {{user_id}}")
      ["user_id"]

      iex> Lotus.Storage.Query.extract_variables_from_statement("SELECT * FROM users")
      []

  """
  @spec extract_variables_from_statement(String.t()) :: [String.t()]
  def extract_variables_from_statement(statement) do
    regex = ~r/\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/

    Regex.scan(regex, statement, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp get_source_type(nil) do
    {_name, repo} = Config.default_data_repo()
    Sources.source_type(repo)
  end

  defp get_source_type(repo_name) when is_binary(repo_name),
    do: Sources.source_type(repo_name)

  defp get_source_type(repo) when is_atom(repo), do: Sources.source_type(repo)

  defp cast_value(value, :number) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} ->
        int_value

      {_int_value, _remainder} ->
        case Float.parse(value) do
          {float_value, ""} ->
            float_value

          {_float_value, _remainder} ->
            raise ArgumentError,
                  "Invalid number format: '#{value}' contains non-numeric characters"

          :error ->
            raise ArgumentError, "Invalid number format: '#{value}' is not a valid number"
        end

      :error ->
        raise ArgumentError, "Invalid number format: '#{value}' is not a valid number"
    end
  end

  defp cast_value(value, :date) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        date

      {:error, _reason} ->
        raise ArgumentError, "Invalid date format: '#{value}' is not a valid ISO8601 date"
    end
  end

  defp cast_value(value, _), do: value

  defp validate_statement(changeset) do
    case get_field(changeset, :statement) do
      nil ->
        changeset

      sql when is_binary(sql) ->
        if String.trim(sql) == "" do
          add_error(changeset, :statement, "cannot be empty")
        else
          changeset
        end

      _ ->
        add_error(changeset, :statement, "must be a string")
    end
  end

  defp validate_data_repo(changeset) do
    case get_change(changeset, :data_repo) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :data_repo, nil)

      repo_name when is_binary(repo_name) ->
        if repo_name in Map.keys(Config.data_repos()) do
          changeset
        else
          add_error(
            changeset,
            :data_repo,
            "must be one of: #{Enum.join(Map.keys(Config.data_repos()), ", ")}"
          )
        end

      _ ->
        add_error(changeset, :data_repo, "must be a string")
    end
  end

  defp validate_search_path(changeset) do
    case get_change(changeset, :search_path) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :search_path, nil)

      sp when is_binary(sp) ->
        if valid_search_path?(sp),
          do: changeset,
          else:
            add_error(changeset, :search_path, "must be a comma-separated list of identifiers")

      _ ->
        add_error(changeset, :search_path, "is invalid")
    end
  end

  defp valid_search_path?(sp) do
    sp
    |> String.split(",")
    |> Enum.all?(fn schema ->
      schema = String.trim(schema)
      Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, schema)
    end)
  end

  defp maybe_add_unique_constraint(changeset) do
    if Config.unique_names?() do
      unique_constraint(changeset, :name, name: "lotus_queries_name_index")
    else
      changeset
    end
  end
end
