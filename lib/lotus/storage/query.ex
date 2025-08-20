defmodule Lotus.Storage.Query do
  @moduledoc """
  Represents a saved Lotus query.

  Queries can be stored, updated, listed, and executed by the host app.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Lotus.Config

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  json_encoder = Lotus.JSON.encoder()

  @derive {json_encoder,
           only: [:id, :name, :description, :query, :tags, :inserted_at, :updated_at]}

  @permitted ~w(name description query tags)a
  @required ~w(name query)a

  @type t :: %__MODULE__{
          id: term(),
          name: String.t(),
          description: String.t() | nil,
          query: map(),
          tags: [String.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "lotus_queries" do
    field(:name, :string)
    field(:description, :string)
    field(:query, :map)
    field(:tags, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Build a new `Lotus.Storage.Query` struct from attributes.

  Does not persist to the database.
  """
  @spec new(map()) :: Ecto.Changeset.t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Update an existing `Lotus.Storage.Query` struct with new attributes.

  Does not persist to the database.
  """
  @spec update(t(), map()) :: Ecto.Changeset.t()
  def update(%__MODULE__{} = query, attrs) when is_map(attrs) do
    changeset(query, attrs)
  end

  @spec to_sql_params(t()) :: {String.t(), list(any())}
  def to_sql_params(%__MODULE__{query: %{"sql" => sql, "params" => params}}) do
    {sql, params || []}
  end

  def to_sql_params(%__MODULE__{query: %{"sql" => sql}}) do
    {sql, []}
  end

  def to_sql_params(%__MODULE__{query: %{sql: sql, params: params}}) do
    {sql, params || []}
  end

  def to_sql_params(%__MODULE__{query: %{sql: sql}}) do
    {sql, []}
  end

  defp changeset(query, attrs) do
    query
    |> cast(attrs, @permitted)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_change(:query, &validate_query_payload/2)
    |> maybe_add_unique_constraint()
    |> put_normalized_tags()
  end

  defp maybe_add_unique_constraint(changeset) do
    if Config.unique_names?() do
      unique_constraint(changeset, :name, name: "lotus_queries_name_index")
    else
      changeset
    end
  end

  defp validate_query_payload(:query, %{"sql" => sql} = q) when is_binary(sql) do
    cond do
      String.trim(sql) == "" ->
        [query: "sql cannot be empty"]

      Map.has_key?(q, "params") and not is_list(q["params"]) ->
        [query: "params must be a list when present"]

      true ->
        []
    end
  end

  defp validate_query_payload(:query, %{sql: sql} = q) when is_binary(sql) do
    cond do
      String.trim(sql) == "" ->
        [query: "sql cannot be empty"]

      Map.has_key?(q, :params) and not is_list(q[:params]) ->
        [query: "params must be a list when present"]

      true ->
        []
    end
  end

  defp validate_query_payload(:query, _),
    do: [query: "must include sql (string) and optionally params (list)"]

  defp put_normalized_tags(changeset) do
    tags = get_change(changeset, :tags)

    if is_list(tags) do
      norm =
        tags
        |> Enum.map(&String.downcase(String.trim(&1)))
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      put_change(changeset, :tags, norm)
    else
      changeset
    end
  end
end
