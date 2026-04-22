defmodule Lotus.Source.Adapters.Ecto.Dialects.SQLite3.EditorConfig do
  @moduledoc false

  def config do
    %{
      language: "sql",
      keywords: ~w(AUTOINCREMENT GLOB PRAGMA VACUUM ATTACH DETACH REINDEX EXPLAIN QUERY PLAN
           ABORT FAIL ROLLBACK DEFERRED IMMEDIATE EXCLUSIVE BEGIN COMMIT SAVEPOINT RELEASE
           CONFLICT REPLACE INSTEAD TRIGGER EACH ROW BEFORE AFTER VIRTUAL USING
           WITHOUT ROWID STRICT INDEXED UNINDEXED MATCH REGEXP),
      types: ~w(INTEGER REAL TEXT BLOB NUMERIC BOOLEAN DATETIME DATE),
      functions: [
        %{name: "typeof", detail: "Type of value", args: "(value)"},
        %{name: "printf", detail: "Format string", args: "(format, ...)"},
        %{name: "unicode", detail: "Unicode code point", args: "(string)"},
        %{name: "instr", detail: "Find substring", args: "(string, substring)"},
        %{name: "json_extract", detail: "Extract JSON value", args: "(json, path)"},
        %{name: "json_group_array", detail: "Aggregate as JSON array", args: "(value)"},
        %{name: "json_group_object", detail: "Aggregate as JSON object", args: "(name, value)"},
        %{name: "json_array", detail: "Build JSON array", args: "(value, ...)"},
        %{name: "json_object", detail: "Build JSON object", args: "(label, value, ...)"},
        %{name: "json_type", detail: "JSON value type", args: "(json[, path])"},
        %{name: "json_valid", detail: "Check valid JSON", args: "(json)"},
        %{name: "json_array_length", detail: "JSON array length", args: "(json[, path])"},
        %{name: "json_insert", detail: "Insert into JSON", args: "(json, path, value, ...)"},
        %{name: "json_replace", detail: "Replace in JSON", args: "(json, path, value, ...)"},
        %{name: "json_set", detail: "Set JSON value", args: "(json, path, value, ...)"},
        %{name: "json_remove", detail: "Remove from JSON", args: "(json, path, ...)"},
        %{name: "json_each", detail: "Expand JSON to rows", args: "(json[, path])"},
        %{name: "json_tree", detail: "Walk JSON tree", args: "(json[, path])"},
        %{name: "zeroblob", detail: "Zero-filled blob", args: "(N)"},
        %{name: "total_changes", detail: "Total rows changed", args: "()"},
        %{name: "changes", detail: "Rows changed by last", args: "()"},
        %{name: "last_insert_rowid", detail: "Last rowid", args: "()"},
        %{name: "random", detail: "Random integer", args: "()"},
        %{name: "hex", detail: "Hex representation", args: "(value)"},
        %{name: "unhex", detail: "Decode hex", args: "(string)"},
        %{name: "quote", detail: "SQL-quote value", args: "(value)"},
        %{name: "likelihood", detail: "Optimizer hint", args: "(value, probability)"},
        %{name: "group_concat", detail: "Concatenate group", args: "(value[, separator])"},
        %{name: "total", detail: "Sum (returns 0.0 for empty)", args: "(value)"},
        %{name: "iif", detail: "Inline if", args: "(condition, then, else)"},
        %{name: "row_number", detail: "Row number", args: "()"},
        %{name: "rank", detail: "Rank with gaps", args: "()"},
        %{name: "dense_rank", detail: "Dense rank", args: "()"},
        %{name: "lag", detail: "Previous row value", args: "(value[, offset[, default]])"},
        %{name: "lead", detail: "Next row value", args: "(value[, offset[, default]])"}
      ],
      context_boundaries: []
    }
  end
end
