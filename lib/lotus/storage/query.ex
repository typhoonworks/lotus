defmodule Lotus.Storage.Query do
  @moduledoc """
  Represents a saved Lotus query.

  Queries can be stored, updated, listed, and executed by the host app.
  Supports `{{var}}` placeholders in the SQL `statement`, which can be
  bound at runtime with `vars:` or defaulted via `var_defaults`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Lotus.Config

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  json_encoder = Lotus.JSON.encoder()

  @derive {json_encoder,
           only: [
             :id,
             :name,
             :description,
             :statement,
             :var_defaults,
             :data_repo,
             :search_path,
             :inserted_at,
             :updated_at
           ]}

  @permitted ~w(name description statement var_defaults data_repo search_path)a
  @required ~w(name statement)a

  @type t :: %__MODULE__{
          id: term(),
          name: String.t(),
          description: String.t() | nil,
          statement: String.t(),
          var_defaults: map(),
          data_repo: String.t() | nil,
          search_path: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "lotus_queries" do
    field(:name, :string)
    field(:description, :string)
    field(:statement, :string)
    field(:var_defaults, :map, default: %{})
    field(:data_repo, :string)
    field(:search_path, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Build a new Query changeset."
  @spec new(map()) :: Ecto.Changeset.t()
  def new(attrs) when is_map(attrs),
    do: %__MODULE__{} |> changeset(attrs)

  @doc "Update an existing Query changeset."
  @spec update(t(), map()) :: Ecto.Changeset.t()
  def update(%__MODULE__{} = query, attrs) when is_map(attrs),
    do: changeset(query, attrs)

  @doc """
  Convert a query struct and variable map into a safe `{sql, params}` tuple.

  Replaces `{{var}}` placeholders in the `statement` with the correct placeholder
  syntax for the underlying database adapter (e.g. `$1, $2, ...` for Postgres,
  `?` for SQLite, etc.).

  The params list is built from the provided `vars` map, falling back to
  `var_defaults` stored with the query. Raises if a required variable has no
  value or default.
  """
  @spec to_sql_params(t(), map()) :: {String.t(), list(any())}
  def to_sql_params(%__MODULE__{statement: sql, var_defaults: defaults} = q, vars \\ %{}) do
    regex = ~r/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/

    vars_in_order =
      Regex.scan(regex, sql)
      |> Enum.map(fn [_, var] -> var end)

    adapter = Lotus.Adapter.param_style(q.data_repo)

    Enum.reduce(
      Enum.with_index(vars_in_order, 1),
      {sql, []},
      fn {var, idx}, {acc_sql, acc_params} ->
        value =
          Map.get(vars, var) ||
            Map.get(defaults || %{}, var) ||
            raise ArgumentError, "Missing required variable: #{var}"

        placeholder =
          case adapter do
            :postgres -> "$#{idx}"
            :sqlite -> "?"
            _ -> "?"
          end

        {
          String.replace(acc_sql, "{{#{var}}}", placeholder, global: false),
          acc_params ++ [value]
        }
      end
    )
  end

  defp changeset(query, attrs) do
    query
    |> cast(attrs, @permitted)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_statement()
    |> validate_var_defaults()
    |> validate_data_repo()
    |> validate_search_path()
    |> maybe_add_unique_constraint()
  end

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

  defp validate_var_defaults(changeset) do
    case get_field(changeset, :var_defaults) do
      nil -> changeset
      m when is_map(m) -> changeset
      _ -> add_error(changeset, :var_defaults, "must be a map")
    end
  end

  defp maybe_add_unique_constraint(changeset) do
    if Config.unique_names?() do
      unique_constraint(changeset, :name, name: "lotus_queries_name_index")
    else
      changeset
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
end
