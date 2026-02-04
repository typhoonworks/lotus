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
  require Logger

  alias Lotus.Config
  alias Lotus.Sources
  alias Lotus.SQL.Transformer
  alias Lotus.Storage.{QueryVariable, SchemaCache, TypeCaster, TypeMapper, VariableResolver}

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
    repo = get_repo(q.data_repo)
    source_type = get_source_type(q.data_repo)
    source_module = get_source_module(repo)

    # Transform SQL for database-specific syntax
    transformed_sql = Transformer.transform(sql, source_type)

    # Extract variables from SQL
    regex = ~r/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/

    vars_in_order =
      Regex.scan(regex, transformed_sql)
      |> Enum.map(fn [_, var] -> var end)

    variable_bindings = VariableResolver.resolve_variables(transformed_sql)

    enriched_bindings =
      enrich_bindings_with_types(variable_bindings, repo, q.search_path, source_module)

    # Build SQL with parameters, using automatic type casting
    Enum.reduce(Enum.with_index(vars_in_order, 1), {transformed_sql, []}, fn {var, idx},
                                                                             {acc_sql, acc_params} ->
      meta = Enum.find(vars, %{}, &(&1.name == var))

      value =
        Map.get(supplied_vars, var) ||
          Map.get(meta, :default) ||
          raise ArgumentError, "Missing required variable: #{var}"

      manual_type = Map.get(meta, :type)
      binding = Enum.find(enriched_bindings, &(&1.variable == var))

      {final_type, casted_value} = determine_type_and_cast(value, manual_type, binding)

      placeholder = Lotus.Source.param_placeholder(q.data_repo, idx, var, final_type)

      {
        String.replace(acc_sql, "{{#{var}}}", placeholder, global: false),
        acc_params ++ [casted_value]
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

  defp get_repo(nil) do
    {_name, repo} = Config.default_data_repo()
    repo
  end

  defp get_repo(repo_name) when is_binary(repo_name) do
    Config.data_repos()
    |> Map.get(repo_name)
    |> case do
      nil -> raise ArgumentError, "Unknown data repo: #{repo_name}"
      repo -> repo
    end
  end

  defp get_repo(repo) when is_atom(repo), do: repo

  defp get_source_type(nil) do
    {_name, repo} = Config.default_data_repo()
    Sources.source_type(repo)
  end

  defp get_source_type(repo_name) when is_binary(repo_name),
    do: Sources.source_type(repo_name)

  defp get_source_type(repo) when is_atom(repo), do: Sources.source_type(repo)

  defp get_source_module(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> Lotus.Sources.Postgres
      Ecto.Adapters.SQLite3 -> Lotus.Sources.SQLite3
      Ecto.Adapters.MyXQL -> Lotus.Sources.MySQL
      _ -> nil
    end
  end

  defp enrich_bindings_with_types(bindings, repo, search_path, source_module) do
    Enum.map(bindings, fn binding ->
      schema = resolve_schema(binding.table, search_path)

      case SchemaCache.get_column_type(repo, schema, binding.table, binding.column) do
        {:ok, db_type} ->
          lotus_type = TypeMapper.db_type_to_lotus_type(db_type, source_module)
          Map.put(binding, :lotus_type, lotus_type)

        :not_found ->
          Logger.debug(
            "Column type not found: #{schema}.#{binding.table}.#{binding.column}, " <>
              "defaulting to :text"
          )

          Map.put(binding, :lotus_type, :text)
      end
    end)
  rescue
    error in [ArgumentError, FunctionClauseError, DBConnection.ConnectionError] ->
      Logger.warning(
        "Type enrichment failed: #{Exception.message(error)}, " <>
          "defaulting all bindings to :text"
      )

      Enum.map(bindings, &Map.put(&1, :lotus_type, :text))
  end

  defp resolve_schema(table, search_path) when is_binary(table) do
    # Check if table name includes schema prefix (e.g., "public.users")
    case String.split(table, ".", parts: 2) do
      [schema, _table_name] ->
        # Explicit schema in table name
        schema

      [_table_name] ->
        # No schema prefix - use search_path or default
        resolve_from_search_path(search_path)
    end
  end

  defp resolve_schema(nil, search_path), do: resolve_from_search_path(search_path)

  defp resolve_from_search_path(search_path) when is_binary(search_path) do
    search_path
    |> String.split(",")
    |> List.first()
    |> case do
      nil -> "public"
      schema -> String.trim(schema)
    end
  end

  defp resolve_from_search_path(_), do: "public"

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp determine_type_and_cast(value, manual_type, binding) do
    cond do
      # If we have automatic detection with a non-text type, prefer it
      binding && Map.has_key?(binding, :lotus_type) && binding.lotus_type != :text ->
        lotus_type = binding.lotus_type
        column_info = %{table: binding.table, column: binding.column}

        if requires_casting?(lotus_type, value) do
          case TypeCaster.cast_value(value, lotus_type, column_info) do
            {:ok, casted_value} ->
              {lotus_type, casted_value}

            {:error, error_msg} ->
              raise ArgumentError, error_msg
          end
        else
          # Pass through without casting for text/varchar
          {lotus_type, value}
        end

      # If automatic detection returned :text but we have a manual type, prefer manual
      manual_type != nil ->
        {manual_type, cast_value(value, manual_type)}

      # If automatic detection found text type and no manual type, use text
      binding && Map.has_key?(binding, :lotus_type) ->
        {binding.lotus_type, value}

      # No type information - use as-is
      true ->
        {nil, value}
    end
  end

  defp requires_casting?(:text, _value), do: false
  defp requires_casting?(:binary, value) when is_binary(value), do: false
  defp requires_casting?(:enum, _value), do: false
  defp requires_casting?(:uuid, _value), do: true
  defp requires_casting?(:number, _value), do: true
  defp requires_casting?(:integer, _value), do: true
  defp requires_casting?(:float, _value), do: true
  defp requires_casting?(:decimal, _value), do: true
  defp requires_casting?(:boolean, _value), do: true
  defp requires_casting?(:date, _value), do: true
  defp requires_casting?(:time, _value), do: true
  defp requires_casting?(:datetime, _value), do: true
  defp requires_casting?(:json, _value), do: true
  defp requires_casting?(:composite, _value), do: true
  defp requires_casting?({:array, _element_type}, _value), do: true
  defp requires_casting?(_, _value), do: false

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
