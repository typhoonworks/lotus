defmodule Lotus.Storage.QueryVisualization do
  @moduledoc """
  Represents a saved visualization configuration for a Lotus query.

  Stores a neutral, renderer-agnostic config map (DSL) that Lotus Web will
  transform into concrete chart specs (e.g., Vega/Recharts).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Lotus.Storage.Query

  @type t :: %__MODULE__{
          id: term(),
          query_id: term(),
          name: String.t(),
          position: non_neg_integer(),
          config: map(),
          version: non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  json_encoder = Lotus.JSON.encoder()

  @derive {json_encoder,
           only: [
             :id,
             :query_id,
             :name,
             :position,
             :config,
             :version,
             :inserted_at,
             :updated_at
           ]}

  schema "lotus_query_visualizations" do
    field(:name, :string)
    field(:position, :integer)
    field(:config, :map)
    field(:version, :integer, default: 1)

    belongs_to(:query, Query, references: :id, type: :id)

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(query_id name position config)a
  @permitted @required ++ ~w(version)a

  def new(attrs), do: changeset(%__MODULE__{}, attrs)
  def update(viz, attrs), do: changeset(viz, attrs)

  def changeset(viz, attrs) do
    viz
    |> cast(attrs, @permitted)
    |> normalize_config()
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_config_shape()
    |> unique_constraint(:name,
      name: "lotus_query_visualizations_query_id_name_index",
      message: "name must be unique within the query"
    )
  end

  defp normalize_config(%Ecto.Changeset{} = cs) do
    case get_change(cs, :config) do
      nil -> cs
      cfg when is_map(cfg) -> put_change(cs, :config, stringify_keys(cfg))
      _ -> cs
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  # Minimal shape validation for the neutral config DSL. Intentional flexibility.
  defp validate_config_shape(%Ecto.Changeset{} = cs) do
    case get_field(cs, :config) do
      %{} = cfg ->
        with :ok <- validate_chart(cfg),
             :ok <- validate_x(cfg),
             :ok <- validate_y(cfg),
             :ok <- validate_series(cfg),
             :ok <- validate_filters(cfg),
             :ok <- validate_options(cfg) do
          cs
        else
          {:error, {field, msg}} -> add_error(cs, field, msg)
        end

      nil ->
        cs

      _ ->
        add_error(cs, :config, "must be a map")
    end
  end

  defp validate_chart(%{"chart" => v}) when is_binary(v) do
    allowed = ["line", "bar", "area", "scatter", "table", "number", "heatmap"]
    if v in allowed, do: :ok, else: {:error, {:config, "invalid chart type"}}
  end

  defp validate_chart(%{chart: v}) when is_binary(v), do: validate_chart(%{"chart" => v})
  defp validate_chart(%{"chart" => _}), do: {:error, {:config, "invalid chart type"}}
  defp validate_chart(%{chart: _}), do: {:error, {:config, "invalid chart type"}}
  defp validate_chart(_), do: {:error, {:config, "chart is required"}}

  defp validate_x(%{"x" => %{} = x}), do: do_validate_x(x)
  defp validate_x(%{x: %{} = x}), do: do_validate_x(x)
  defp validate_x(_cfg), do: :ok

  defp do_validate_x(x) do
    with {:ok, _} <- fetch_string(x, "field"),
         {:ok, kind} <- fetch_string(x, "kind"),
         true <- kind in ["temporal", "quantitative", "nominal"] || {:error, :kind},
         :ok <- validate_optional_string(x, "timeUnit") do
      :ok
    else
      {:error, :kind} -> {:error, {:config, "x.kind must be temporal|quantitative|nominal"}}
      {:error, {k, msg}} -> {:error, {:config, "x.#{k} #{msg}"}}
    end
  end

  defp validate_y(%{"y" => list}) when is_list(list), do: do_validate_y(list)
  defp validate_y(%{y: list}) when is_list(list), do: do_validate_y(list)
  defp validate_y(_cfg), do: :ok

  defp do_validate_y(list) do
    Enum.reduce_while(Enum.with_index(list), :ok, fn {item, idx}, _acc ->
      case do_validate_y_item(item) do
        :ok -> {:cont, :ok}
        {:error, msg} -> {:halt, {:error, {:config, "y[#{idx}] #{msg}"}}}
      end
    end)
  end

  defp do_validate_y_item(%{} = y) do
    with {:ok, _} <- fetch_string(y, "field"),
         :ok <- validate_optional_in(y, "agg", ["sum", "avg", "count"]) do
      :ok
    else
      {:error, {k, msg}} -> {:error, "#{k} #{msg}"}
    end
  end

  defp do_validate_y_item(_), do: {:error, "must be an object"}

  defp validate_series(%{"series" => %{} = s}), do: do_validate_series(s)
  defp validate_series(%{series: %{} = s}), do: do_validate_series(s)
  defp validate_series(_cfg), do: :ok

  defp do_validate_series(s) do
    case fetch_string(s, "field") do
      {:ok, _} -> :ok
      {:error, {k, msg}} -> {:error, {:config, "series.#{k} #{msg}"}}
    end
  end

  defp validate_filters(%{"filters" => list}) when is_list(list), do: do_validate_filters(list)
  defp validate_filters(%{filters: list}) when is_list(list), do: do_validate_filters(list)
  defp validate_filters(_cfg), do: :ok

  defp do_validate_filters(list) do
    allowed_ops = ["=", "!=", "<", "<=", ">", ">=", "in", "not in"]

    Enum.reduce_while(Enum.with_index(list), :ok, fn {item, idx}, _acc ->
      case item do
        %{} = f ->
          with {:ok, _} <- fetch_string(f, "field"),
               {:ok, op} <- fetch_string(f, "op"),
               true <- op in allowed_ops || {:error, :op},
               :ok <- validate_filter_value_present(f) do
            {:cont, :ok}
          else
            {:error, :op} -> {:halt, {:error, {:config, "filters[#{idx}].op invalid"}}}
            {:error, {k, msg}} -> {:halt, {:error, {:config, "filters[#{idx}].#{k} #{msg}"}}}
          end

        _ ->
          {:halt, {:error, {:config, "filters[#{idx}] must be an object"}}}
      end
    end)
  end

  defp validate_filter_value_present(%{"value" => _}), do: :ok
  defp validate_filter_value_present(%{value: _}), do: :ok
  defp validate_filter_value_present(_), do: {:error, {"value", "is required"}}

  defp validate_options(%{"options" => %{} = o}), do: do_validate_options(o)
  defp validate_options(%{options: %{} = o}), do: do_validate_options(o)
  defp validate_options(_cfg), do: :ok

  defp do_validate_options(o) do
    with :ok <- validate_optional_boolean(o, "legend"),
         :ok <- validate_optional_in(o, "stack", ["none", "stack", "normalize"]) do
      :ok
    else
      {:error, {k, msg}} -> {:error, {:config, "options.#{k} #{msg}"}}
    end
  end

  # helpers
  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, v} when is_binary(v) ->
        if String.trim(v) != "", do: {:ok, v}, else: {:error, {key, "must be a non-empty string"}}

      {:ok, _} ->
        {:error, {key, "must be a non-empty string"}}

      :error ->
        {:error, {key, "is required"}}
    end
  end

  defp validate_optional_string(map, key) do
    case Map.get(map, key) do
      nil -> :ok
      v when is_binary(v) -> :ok
      _ -> {:error, {key, "must be a string"}}
    end
  end

  defp validate_optional_boolean(map, key) do
    case Map.get(map, key) do
      nil -> :ok
      v when is_boolean(v) -> :ok
      _ -> {:error, {key, "must be a boolean"}}
    end
  end

  defp validate_optional_in(map, key, allowed) do
    case Map.get(map, key) do
      nil -> :ok
      v when is_binary(v) -> if v in allowed, do: :ok, else: {:error, {key, "has invalid value"}}
      _ -> {:error, {key, "must be a string"}}
    end
  end
end
