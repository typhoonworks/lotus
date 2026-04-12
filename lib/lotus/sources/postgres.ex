defmodule Lotus.Sources.Postgres do
  @moduledoc false

  # Deprecated: use Lotus.Source.Adapters.Ecto.Dialects.Postgres instead.
  # This module delegates all calls to the new location for backward compatibility
  # during the migration. It will be deleted once all references are updated.

  alias Lotus.Source.Adapters.Ecto.Dialects.Postgres, as: PgDialect

  defdelegate execute_in_transaction(repo, fun, opts), to: PgDialect
  defdelegate set_statement_timeout(repo, ms), to: PgDialect
  defdelegate set_search_path(repo, path), to: PgDialect
  defdelegate format_error(error), to: PgDialect
  defdelegate param_placeholder(idx, var, type), to: PgDialect
  defdelegate limit_offset_placeholders(limit_idx, offset_idx), to: PgDialect
  defdelegate handled_errors(), to: PgDialect
  defdelegate query_language(), to: PgDialect
  defdelegate limit_query(statement, limit), to: PgDialect
  defdelegate builtin_denies(repo), to: PgDialect
  defdelegate default_schemas(repo), to: PgDialect
  defdelegate supports_feature?(feature), to: PgDialect
  defdelegate hierarchy_label(), to: PgDialect
  defdelegate example_query(table, schema), to: PgDialect
  defdelegate builtin_schema_denies(repo), to: PgDialect
  defdelegate list_schemas(repo), to: PgDialect
  defdelegate list_tables(repo, schemas, include_views?), to: PgDialect
  defdelegate get_table_schema(repo, schema, table), to: PgDialect
  defdelegate explain_plan(repo, sql, params, opts), to: PgDialect
  defdelegate resolve_table_schema(repo, table, schemas), to: PgDialect
  defdelegate quote_identifier(identifier), to: PgDialect
  defdelegate apply_filters(sql, params, filters), to: PgDialect
  defdelegate apply_sorts(sql, sorts), to: PgDialect
end
