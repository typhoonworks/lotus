defmodule Lotus.Sources.Default do
  @moduledoc false

  # Deprecated: use Lotus.Source.Adapters.Ecto.Dialects.Default instead.

  alias Lotus.Source.Adapters.Ecto.Dialects.Default, as: DefaultDialect

  defdelegate execute_in_transaction(repo, fun, opts), to: DefaultDialect
  defdelegate set_statement_timeout(repo, ms), to: DefaultDialect
  defdelegate set_search_path(repo, path), to: DefaultDialect
  defdelegate format_error(error), to: DefaultDialect
  defdelegate param_placeholder(idx, var, type), to: DefaultDialect
  defdelegate limit_offset_placeholders(limit_idx, offset_idx), to: DefaultDialect
  defdelegate handled_errors(), to: DefaultDialect
  defdelegate query_language(), to: DefaultDialect
  defdelegate limit_query(statement, limit), to: DefaultDialect
  defdelegate builtin_denies(repo), to: DefaultDialect
  defdelegate default_schemas(repo), to: DefaultDialect
  defdelegate supports_feature?(feature), to: DefaultDialect
  defdelegate hierarchy_label(), to: DefaultDialect
  defdelegate example_query(table, schema), to: DefaultDialect
  defdelegate builtin_schema_denies(repo), to: DefaultDialect
  defdelegate list_schemas(repo), to: DefaultDialect
  defdelegate list_tables(repo, schemas, include_views?), to: DefaultDialect
  defdelegate get_table_schema(repo, schema, table), to: DefaultDialect
  defdelegate explain_plan(repo, sql, params, opts), to: DefaultDialect
  defdelegate resolve_table_schema(repo, table, schemas), to: DefaultDialect
  defdelegate quote_identifier(identifier), to: DefaultDialect
  defdelegate apply_filters(sql, params, filters), to: DefaultDialect
  defdelegate apply_sorts(sql, sorts), to: DefaultDialect
end
