defmodule Lotus.Test.NoOpAdapter do
  @moduledoc false
  @behaviour Lotus.Source.Adapter

  @impl true
  def extract_accessed_resources(_state, _query, _params, _opts), do: :skip

  @impl true
  def execute_query(_state, _sql, _params, _opts), do: {:error, "not implemented"}
  @impl true
  def transaction(_state, _fun, _opts), do: {:error, "not implemented"}
  @impl true
  def list_schemas(_state), do: {:ok, []}
  @impl true
  def list_tables(_state, _schemas, _opts), do: {:ok, []}
  @impl true
  def get_table_schema(_state, _schema, _table), do: {:ok, []}
  @impl true
  def resolve_table_schema(_state, _table, _schemas), do: {:ok, nil}
  @impl true
  def quote_identifier(_state, id), do: ~s("#{id}")
  @impl true
  def param_placeholder(_state, index, _var, _type), do: "$#{index}"
  @impl true
  def limit_offset_placeholders(_state, li, oi), do: {"$#{li}", "$#{oi}"}
  @impl true
  def apply_filters(_state, sql, params, _filters), do: {sql, params}
  @impl true
  def apply_sorts(_state, sql, _sorts), do: sql
  @impl true
  def explain_plan(_state, _sql, _params, _opts), do: {:ok, ""}
  @impl true
  def builtin_denies(_state), do: []
  @impl true
  def builtin_schema_denies(_state), do: []
  @impl true
  def default_schemas(_state), do: []
  @impl true
  def health_check(_state), do: :ok
  @impl true
  def disconnect(_state), do: :ok
  @impl true
  def format_error(_state, error), do: inspect(error)
  @impl true
  def handled_errors(_state), do: []
  @impl true
  def source_type(_state), do: :other
  @impl true
  def supports_feature?(_state, _feature), do: false
end

defmodule Lotus.Test.StubAdapter do
  @moduledoc false
  @behaviour Lotus.Source.Adapter

  @impl true
  def execute_query(_state, _sql, _params, _opts), do: {:error, "not implemented"}
  @impl true
  def transaction(_state, _fun, _opts), do: {:error, "not implemented"}
  @impl true
  def list_schemas(_state), do: {:ok, []}
  @impl true
  def list_tables(_state, _schemas, _opts), do: {:ok, []}
  @impl true
  def get_table_schema(_state, _schema, _table), do: {:ok, []}
  @impl true
  def resolve_table_schema(_state, _table, _schemas), do: {:ok, nil}
  @impl true
  def quote_identifier(_state, id), do: ~s("#{id}")
  @impl true
  def param_placeholder(_state, index, _var, _type), do: "$#{index}"
  @impl true
  def limit_offset_placeholders(_state, li, oi), do: {"$#{li}", "$#{oi}"}
  @impl true
  def apply_filters(_state, sql, params, _filters), do: {sql, params}
  @impl true
  def apply_sorts(_state, sql, _sorts), do: sql
  @impl true
  def explain_plan(_state, _sql, _params, _opts), do: {:ok, ""}
  @impl true
  def builtin_denies(_state), do: []
  @impl true
  def builtin_schema_denies(_state), do: []
  @impl true
  def default_schemas(_state), do: []
  @impl true
  def health_check(_state), do: :ok
  @impl true
  def disconnect(_state), do: :ok
  @impl true
  def format_error(_state, error), do: inspect(error)
  @impl true
  def handled_errors(_state), do: []
  @impl true
  def source_type(_state), do: :other
  @impl true
  def supports_feature?(_state, _feature), do: false
end
