defmodule Lotus.Sources.SQLite3 do
  @moduledoc false

  # Deprecated: use Lotus.Source.Adapters.Ecto.Dialects.SQLite3 instead.

  require Logger

  alias Lotus.Source.Adapters.Ecto.Dialects.SQLite3, as: SQLiteDialect

  defdelegate execute_in_transaction(repo, fun, opts), to: SQLiteDialect
  defdelegate set_statement_timeout(repo, ms), to: SQLiteDialect
  defdelegate set_search_path(repo, path), to: SQLiteDialect
  defdelegate format_error(error), to: SQLiteDialect
  defdelegate param_placeholder(idx, var, type), to: SQLiteDialect
  defdelegate limit_offset_placeholders(limit_idx, offset_idx), to: SQLiteDialect
  defdelegate handled_errors(), to: SQLiteDialect
  defdelegate query_language(), to: SQLiteDialect
  defdelegate limit_query(statement, limit), to: SQLiteDialect
  defdelegate builtin_denies(repo), to: SQLiteDialect
  defdelegate default_schemas(repo), to: SQLiteDialect
  defdelegate supports_feature?(feature), to: SQLiteDialect
  defdelegate hierarchy_label(), to: SQLiteDialect
  defdelegate example_query(table, schema), to: SQLiteDialect
  defdelegate builtin_schema_denies(repo), to: SQLiteDialect
  defdelegate list_schemas(repo), to: SQLiteDialect
  defdelegate list_tables(repo, schemas, include_views?), to: SQLiteDialect
  defdelegate get_table_schema(repo, schema, table), to: SQLiteDialect
  defdelegate explain_plan(repo, sql, params, opts), to: SQLiteDialect
  defdelegate resolve_table_schema(repo, table, schemas), to: SQLiteDialect
  defdelegate quote_identifier(identifier), to: SQLiteDialect
  defdelegate apply_filters(sql, params, filters), to: SQLiteDialect
  defdelegate apply_sorts(sql, sorts), to: SQLiteDialect
end
