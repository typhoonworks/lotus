defmodule Lotus.Source.Adapters.Ecto.Dialects.Default do
  @moduledoc false

  @behaviour Lotus.Source.Adapters.Ecto.Dialect

  alias Lotus.SQL.FilterInjector
  alias Lotus.SQL.SortInjector

  @impl true
  def source_type, do: :other

  @impl true
  def ecto_adapter, do: nil

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    timeout = Keyword.get(opts, :timeout, 15_000)

    repo.transaction(fun, timeout: timeout)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def set_statement_timeout(_repo, _ms), do: :ok

  @impl true
  def set_search_path(_repo, _path), do: :ok

  @impl true
  def format_error(%{__exception__: true} = e), do: Exception.message(e)
  def format_error(%DBConnection.EncodeError{message: msg}), do: msg
  def format_error(%ArgumentError{message: msg}), do: msg
  def format_error(msg) when is_binary(msg), do: msg
  def format_error(other), do: "Database Error: #{inspect(other)}"

  @impl true
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  def limit_offset_placeholders(_limit_idx, _offset_idx) do
    {"?", "?"}
  end

  @impl true
  def handled_errors, do: []

  @impl true
  def query_language, do: "sql"

  @impl true
  def limit_query(statement, limit) do
    "SELECT * FROM (#{statement}) AS limited_query LIMIT #{limit}"
  end

  @impl true
  def builtin_denies(_repo) do
    [
      {"pg_catalog", ~r/.*/},
      {"information_schema", ~r/.*/},
      {nil, ~r/^sqlite_/},
      {nil, "schema_migrations"},
      {"public", "schema_migrations"},
      {"public", "lotus_queries"},
      {nil, "lotus_queries"},
      {"public", "lotus_query_visualizations"},
      {nil, "lotus_query_visualizations"},
      {"public", "lotus_dashboards"},
      {nil, "lotus_dashboards"},
      {"public", "lotus_dashboard_cards"},
      {nil, "lotus_dashboard_cards"},
      {"public", "lotus_dashboard_filters"},
      {nil, "lotus_dashboard_filters"},
      {"public", "lotus_dashboard_card_filter_mappings"},
      {nil, "lotus_dashboard_card_filter_mappings"}
    ]
  end

  @impl true
  def default_schemas(_repo) do
    ["public"]
  end

  @impl true
  def supports_feature?(_), do: false

  @impl true
  def hierarchy_label, do: "Tables"

  @impl true
  def example_query(table, _schema) do
    "SELECT value_column FROM #{table}"
  end

  @impl true
  def builtin_schema_denies(_repo) do
    ["pg_catalog", "information_schema", "mysql", "performance_schema", "sys"]
  end

  @impl true
  def list_schemas(_repo) do
    []
  end

  @impl true
  def list_tables(_repo, _schemas, _include_views?) do
    []
  end

  @impl true
  def get_table_schema(_repo, _schema, _table) do
    []
  end

  @impl true
  def explain_plan(_repo, _sql, _params, _opts) do
    {:error, "EXPLAIN not supported for this database adapter"}
  end

  @impl true
  def resolve_table_schema(_repo, _table, _schemas) do
    nil
  end

  @impl true
  def quote_identifier(identifier) do
    escaped = String.replace(identifier, "\"", "\"\"")
    ~s("#{escaped}")
  end

  @impl true
  def apply_filters(sql, params, filters) do
    FilterInjector.apply(sql, params, filters, &quote_identifier/1, fn _idx -> "?" end)
  end

  @impl true
  def apply_sorts(sql, sorts) do
    SortInjector.apply(sql, sorts, &quote_identifier/1)
  end

  @impl true
  def editor_config do
    Lotus.Source.Adapters.Ecto.Dialects.Default.EditorConfig.config()
  end
end
