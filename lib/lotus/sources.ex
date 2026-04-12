defmodule Lotus.Sources do
  @moduledoc false

  # Deprecated: use Lotus.Source instead.
  # This module delegates all calls to the new facade for backward compatibility.

  defdelegate resolve!(source_opt, q_source), to: Lotus.Source
  defdelegate list_sources(), to: Lotus.Source
  defdelegate get_source!(name), to: Lotus.Source
  defdelegate default_source(), to: Lotus.Source
  defdelegate name_from_module!(mod), to: Lotus.Source
  defdelegate source_type(source), to: Lotus.Source
  defdelegate supports_feature?(source, feature), to: Lotus.Source
  defdelegate hierarchy_label(source), to: Lotus.Source
  defdelegate example_query(source, table, schema), to: Lotus.Source
  defdelegate query_language(source), to: Lotus.Source
  defdelegate limit_query(source, statement, limit), to: Lotus.Source
end
