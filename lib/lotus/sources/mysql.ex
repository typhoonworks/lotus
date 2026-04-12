defmodule Lotus.Sources.MySQL do
  @moduledoc false

  # Deprecated: use Lotus.Source.Adapters.Ecto.Dialects.MySQL instead.

  require Logger

  alias Lotus.Source.Adapters.Ecto.Dialects.MySQL, as: MySQLDialect

  defdelegate execute_in_transaction(repo, fun, opts), to: MySQLDialect
  defdelegate set_statement_timeout(repo, ms), to: MySQLDialect
  defdelegate set_search_path(repo, path), to: MySQLDialect
  defdelegate format_error(error), to: MySQLDialect
  defdelegate param_placeholder(idx, var, type), to: MySQLDialect
  defdelegate limit_offset_placeholders(limit_idx, offset_idx), to: MySQLDialect
  defdelegate handled_errors(), to: MySQLDialect
  defdelegate query_language(), to: MySQLDialect
  defdelegate limit_query(statement, limit), to: MySQLDialect
  defdelegate builtin_denies(repo), to: MySQLDialect
  defdelegate default_schemas(repo), to: MySQLDialect
  defdelegate supports_feature?(feature), to: MySQLDialect
  defdelegate hierarchy_label(), to: MySQLDialect
  defdelegate example_query(table, schema), to: MySQLDialect
  defdelegate builtin_schema_denies(repo), to: MySQLDialect
  defdelegate list_schemas(repo), to: MySQLDialect
  defdelegate list_tables(repo, schemas, include_views?), to: MySQLDialect
  defdelegate get_table_schema(repo, schema, table), to: MySQLDialect
  defdelegate explain_plan(repo, sql, params, opts), to: MySQLDialect
  defdelegate resolve_table_schema(repo, table, schemas), to: MySQLDialect
  defdelegate quote_identifier(identifier), to: MySQLDialect
  defdelegate apply_filters(sql, params, filters), to: MySQLDialect
  defdelegate apply_sorts(sql, sorts), to: MySQLDialect
end
