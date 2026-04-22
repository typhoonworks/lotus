defmodule Lotus.Source.Adapters.Ecto.Dialects.MySQL.EditorConfig do
  @moduledoc false

  def config do
    %{
      language: "sql",
      keywords:
        ~w(AUTO_INCREMENT ENGINE UNSIGNED ZEROFILL IF ELSEIF ITERATE LEAVE LOOP REPEAT WHILE
           DELIMITER PREPARE EXECUTE DEALLOCATE HANDLER LOAD DATA INFILE OUTFILE DUMPFILE
           LOCK TABLES UNLOCK FLUSH RESET PURGE BINARY MASTER SLAVE CHANGE
           START STOP SHOW DESCRIBE USE KILL PROCESSLIST STATUS VARIABLES
           EXPLAIN EXTENDED PARTITIONS ANALYSE OPTIMIZE REPAIR CHECK CHECKSUM
           DUPLICATE KEY ON IGNORE REPLACE STRAIGHT_JOIN SQL_CALC_FOUND_ROWS
           HIGH_PRIORITY LOW_PRIORITY DELAYED FORCE SPATIAL FULLTEXT),
      types: ~w(tinyint mediumint int unsigned bigint unsigned
           tinytext mediumtext longtext
           tinyblob mediumblob longblob
           enum set year
           datetime timestamp
           geometry point linestring polygon
           multipoint multilinestring multipolygon geometrycollection),
      functions: [
        %{
          name: "GROUP_CONCAT",
          detail: "Concatenate group values",
          args: "(expression SEPARATOR ',')"
        },
        %{name: "IFNULL", detail: "If null use default", args: "(expr, default)"},
        %{name: "IF", detail: "Conditional", args: "(condition, then, else)"},
        %{name: "NULLIF", detail: "Null if equal", args: "(expr1, expr2)"},
        %{name: "DATE_FORMAT", detail: "Format date", args: "(date, format)"},
        %{name: "STR_TO_DATE", detail: "Parse date string", args: "(string, format)"},
        %{name: "DATE_ADD", detail: "Add interval", args: "(date, INTERVAL expr unit)"},
        %{name: "DATE_SUB", detail: "Subtract interval", args: "(date, INTERVAL expr unit)"},
        %{name: "DATEDIFF", detail: "Difference in days", args: "(date1, date2)"},
        %{
          name: "TIMESTAMPDIFF",
          detail: "Difference in units",
          args: "(unit, datetime1, datetime2)"
        },
        %{name: "CURDATE", detail: "Current date", args: "()"},
        %{name: "CURTIME", detail: "Current time", args: "()"},
        %{name: "NOW", detail: "Current datetime", args: "()"},
        %{name: "UNIX_TIMESTAMP", detail: "Unix timestamp", args: "([date])"},
        %{name: "FROM_UNIXTIME", detail: "From unix timestamp", args: "(timestamp[, format])"},
        %{name: "FIND_IN_SET", detail: "Find in comma list", args: "(string, string_list)"},
        %{name: "FIELD", detail: "Index of value", args: "(str, str1, str2, ...)"},
        %{name: "ELT", detail: "Return Nth string", args: "(N, str1, str2, ...)"},
        %{name: "CONV", detail: "Convert number base", args: "(N, from_base, to_base)"},
        %{name: "HEX", detail: "Hex representation", args: "(value)"},
        %{name: "UNHEX", detail: "Decode hex", args: "(string)"},
        %{name: "BIN", detail: "Binary representation", args: "(N)"},
        %{name: "LPAD", detail: "Left pad", args: "(string, length, pad)"},
        %{name: "RPAD", detail: "Right pad", args: "(string, length, pad)"},
        %{name: "REVERSE", detail: "Reverse string", args: "(string)"},
        %{name: "LOCATE", detail: "Find substring", args: "(substr, str[, pos])"},
        %{name: "INSTR", detail: "Find substring position", args: "(string, substring)"},
        %{name: "JSON_EXTRACT", detail: "Extract JSON value", args: "(json, path)"},
        %{name: "JSON_UNQUOTE", detail: "Unquote JSON string", args: "(json)"},
        %{name: "JSON_OBJECT", detail: "Build JSON object", args: "(key, value, ...)"},
        %{name: "JSON_ARRAY", detail: "Build JSON array", args: "(value, ...)"},
        %{name: "JSON_ARRAYAGG", detail: "Aggregate as JSON array", args: "(expression)"},
        %{name: "JSON_OBJECTAGG", detail: "Aggregate as JSON object", args: "(key, value)"},
        %{name: "JSON_CONTAINS", detail: "Check JSON contains", args: "(json, value[, path])"},
        %{name: "JSON_LENGTH", detail: "JSON element count", args: "(json[, path])"},
        %{name: "FOUND_ROWS", detail: "Rows from last query", args: "()"},
        %{name: "LAST_INSERT_ID", detail: "Last auto-increment", args: "()"},
        %{name: "ROW_NUMBER", detail: "Row number", args: "()"},
        %{name: "RANK", detail: "Rank with gaps", args: "()"},
        %{name: "DENSE_RANK", detail: "Dense rank", args: "()"},
        %{name: "LAG", detail: "Previous row value", args: "(value[, offset[, default]])"},
        %{name: "LEAD", detail: "Next row value", args: "(value[, offset[, default]])"}
      ],
      context_boundaries: []
    }
  end
end
