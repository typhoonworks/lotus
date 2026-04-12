defmodule Lotus.Source.Adapters.Ecto.Dialects.Postgres.EditorConfig do
  @moduledoc false

  def config do
    %{
      language: "sql",
      keywords: ~w(RETURNING ILIKE SIMILAR LATERAL MATERIALIZED RECURSIVE CONFLICT
           DO NOTHING LOCK SHARE EXCLUSIVE NOWAIT SKIP LOCKED
           EXPLAIN ANALYZE VERBOSE BUFFERS COSTS FORMAT
           NOTIFY LISTEN UNLISTEN VACUUM REINDEX CLUSTER
           COPY DELIMITER HEADER CSV FREEZE FORCE_NULL FORCE_NOT_NULL
           INHERITS TABLESPACE CONCURRENTLY ONLY TABLESAMPLE),
      types: ~w(serial bigserial smallserial text citext name
           jsonb json hstore xml
           uuid inet cidr macaddr macaddr8
           money
           bytea bit varbit
           timestamptz timetz interval
           point line lseg box path polygon circle
           int4range int8range numrange tsrange tstzrange daterange
           tsvector tsquery regclass oid),
      functions: [
        %{name: "array_agg", detail: "Aggregate into array", args: "(expression)"},
        %{
          name: "string_agg",
          detail: "Concatenate with separator",
          args: "(expression, delimiter)"
        },
        %{name: "json_build_object", detail: "Build JSON object", args: "(key, value, ...)"},
        %{name: "jsonb_build_object", detail: "Build JSONB object", args: "(key, value, ...)"},
        %{name: "json_agg", detail: "Aggregate as JSON array", args: "(expression)"},
        %{name: "jsonb_agg", detail: "Aggregate as JSONB array", args: "(expression)"},
        %{name: "json_extract_path", detail: "Extract JSON path", args: "(json, path...)"},
        %{
          name: "jsonb_extract_path_text",
          detail: "Extract JSONB as text",
          args: "(json, path...)"
        },
        %{name: "row_to_json", detail: "Row to JSON", args: "(record)"},
        %{name: "to_json", detail: "Convert to JSON", args: "(value)"},
        %{name: "to_jsonb", detail: "Convert to JSONB", args: "(value)"},
        %{name: "generate_series", detail: "Generate series", args: "(start, stop[, step])"},
        %{name: "date_trunc", detail: "Truncate to precision", args: "('precision', timestamp)"},
        %{name: "date_part", detail: "Extract date part", args: "('field', source)"},
        %{name: "age", detail: "Interval between", args: "(timestamp[, timestamp])"},
        %{
          name: "make_interval",
          detail: "Construct interval",
          args: "(years => 0, months => 0, ...)"
        },
        %{
          name: "clock_timestamp",
          detail: "Current timestamp (changes during statement)",
          args: "()"
        },
        %{name: "statement_timestamp", detail: "Start of statement timestamp", args: "()"},
        %{name: "transaction_timestamp", detail: "Start of transaction timestamp", args: "()"},
        %{name: "regexp_matches", detail: "Regex matches", args: "(string, pattern[, flags])"},
        %{
          name: "regexp_replace",
          detail: "Regex replace",
          args: "(string, pattern, replacement[, flags])"
        },
        %{
          name: "regexp_split_to_array",
          detail: "Split by regex",
          args: "(string, pattern[, flags])"
        },
        %{
          name: "regexp_split_to_table",
          detail: "Split by regex into rows",
          args: "(string, pattern[, flags])"
        },
        %{name: "string_to_array", detail: "Split to array", args: "(string, delimiter)"},
        %{name: "array_to_string", detail: "Join array", args: "(array, delimiter)"},
        %{name: "unnest", detail: "Expand array to rows", args: "(array)"},
        %{name: "array_length", detail: "Array length", args: "(array, dimension)"},
        %{name: "array_append", detail: "Append to array", args: "(array, element)"},
        %{name: "array_remove", detail: "Remove from array", args: "(array, element)"},
        %{name: "format", detail: "Format string", args: "(formatstr, ...)"},
        %{name: "left", detail: "Left substring", args: "(string, n)"},
        %{name: "right", detail: "Right substring", args: "(string, n)"},
        %{name: "md5", detail: "MD5 hash", args: "(string)"},
        %{name: "encode", detail: "Encode binary", args: "(data, format)"},
        %{name: "decode", detail: "Decode binary", args: "(string, format)"},
        %{name: "pg_size_pretty", detail: "Human-readable size", args: "(bigint)"},
        %{name: "pg_total_relation_size", detail: "Total table size", args: "('relation')"},
        %{name: "pg_relation_size", detail: "Table size", args: "('relation')"},
        %{name: "to_char", detail: "Format to string", args: "(value, format)"},
        %{name: "to_date", detail: "Parse date", args: "(string, format)"},
        %{name: "to_timestamp", detail: "Parse timestamp", args: "(string, format)"},
        %{name: "to_number", detail: "Parse number", args: "(string, format)"},
        %{name: "bool_and", detail: "Boolean AND aggregate", args: "(expression)"},
        %{name: "bool_or", detail: "Boolean OR aggregate", args: "(expression)"},
        %{name: "every", detail: "Alias for bool_and", args: "(expression)"},
        %{name: "percentile_cont", detail: "Continuous percentile", args: "(fraction)"},
        %{name: "percentile_disc", detail: "Discrete percentile", args: "(fraction)"},
        %{name: "mode", detail: "Most frequent value", args: "()"},
        %{name: "dense_rank", detail: "Dense rank", args: "()"},
        %{name: "rank", detail: "Rank with gaps", args: "()"},
        %{name: "row_number", detail: "Row number", args: "()"},
        %{name: "lag", detail: "Previous row value", args: "(value[, offset[, default]])"},
        %{name: "lead", detail: "Next row value", args: "(value[, offset[, default]])"},
        %{name: "first_value", detail: "First value in window", args: "(value)"},
        %{name: "last_value", detail: "Last value in window", args: "(value)"},
        %{name: "nth_value", detail: "Nth value in window", args: "(value, n)"},
        %{name: "ntile", detail: "Divide into buckets", args: "(num_buckets)"},
        %{name: "cume_dist", detail: "Cumulative distribution", args: "()"},
        %{name: "percent_rank", detail: "Relative rank", args: "()"}
      ],
      context_boundaries: []
    }
  end
end
