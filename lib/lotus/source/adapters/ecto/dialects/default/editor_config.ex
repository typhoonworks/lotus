defmodule Lotus.Source.Adapters.Ecto.Dialects.Default.EditorConfig do
  @moduledoc false

  def config do
    %{
      language: "sql",
      keywords:
        ~w(SELECT FROM WHERE JOIN INNER LEFT RIGHT FULL OUTER CROSS ON AS AND OR NOT IN EXISTS
           LIKE BETWEEN CASE WHEN THEN ELSE END DISTINCT ALL UNION INTERSECT EXCEPT WITH
           INSERT INTO VALUES UPDATE SET DELETE CREATE DROP ALTER TABLE INDEX VIEW
           GROUP BY ORDER BY HAVING LIMIT OFFSET ASC DESC NULLS FIRST LAST
           IS NULL TRUE FALSE CAST COALESCE OVER PARTITION ROWS RANGE UNBOUNDED PRECEDING
           FOLLOWING CURRENT ROW FETCH NEXT ONLY),
      types: ~w(INTEGER BIGINT SMALLINT TINYINT FLOAT DOUBLE REAL DECIMAL NUMERIC
           VARCHAR CHAR TEXT CLOB BLOB BINARY VARBINARY
           BOOLEAN DATE TIME TIMESTAMP INTERVAL UUID JSON),
      functions: [
        %{name: "COUNT", detail: "Count rows", args: "(*)"},
        %{name: "SUM", detail: "Sum values", args: "(column)"},
        %{name: "AVG", detail: "Average values", args: "(column)"},
        %{name: "MAX", detail: "Maximum value", args: "(column)"},
        %{name: "MIN", detail: "Minimum value", args: "(column)"},
        %{name: "COALESCE", detail: "First non-null", args: "(value, ...)"},
        %{name: "NULLIF", detail: "Null if equal", args: "(a, b)"},
        %{name: "CAST", detail: "Type cast", args: "(expr AS type)"},
        %{name: "UPPER", detail: "Uppercase", args: "(string)"},
        %{name: "LOWER", detail: "Lowercase", args: "(string)"},
        %{name: "TRIM", detail: "Trim whitespace", args: "(string)"},
        %{name: "LENGTH", detail: "String length", args: "(string)"},
        %{name: "SUBSTRING", detail: "Substring", args: "(string, start, length)"},
        %{name: "REPLACE", detail: "Replace substring", args: "(string, from, to)"},
        %{name: "CONCAT", detail: "Concatenate", args: "(a, b, ...)"},
        %{name: "ABS", detail: "Absolute value", args: "(number)"},
        %{name: "ROUND", detail: "Round number", args: "(number, decimals)"},
        %{name: "CEIL", detail: "Ceiling", args: "(number)"},
        %{name: "FLOOR", detail: "Floor", args: "(number)"},
        %{name: "NOW", detail: "Current timestamp", args: "()"},
        %{name: "CURRENT_DATE", detail: "Current date", args: ""},
        %{name: "CURRENT_TIMESTAMP", detail: "Current timestamp", args: ""},
        %{name: "EXTRACT", detail: "Extract date part", args: "(part FROM date)"},
        %{name: "DISTINCT", detail: "Unique values", args: "(column)"}
      ],
      context_boundaries: []
    }
  end
end
