defmodule Lotus.Source.Adapters.Ecto.Dialect do
  @moduledoc false

  @type repo :: Ecto.Repo.t()

  # ---------------------------------------------------------------------------
  # Required callbacks — Session management
  # ---------------------------------------------------------------------------

  @callback execute_in_transaction(repo, (-> any()), keyword()) :: {:ok, any()} | {:error, any()}
  @callback set_statement_timeout(repo, non_neg_integer()) :: :ok | no_return()
  @callback set_search_path(repo, String.t()) :: :ok | no_return()

  # ---------------------------------------------------------------------------
  # Required callbacks — Error handling
  # ---------------------------------------------------------------------------

  @callback format_error(any()) :: String.t()
  @callback handled_errors() :: [module()]

  # ---------------------------------------------------------------------------
  # Required callbacks — SQL generation
  # ---------------------------------------------------------------------------

  @callback quote_identifier(String.t()) :: String.t()

  @callback param_placeholder(index :: pos_integer(), var :: String.t(), type :: atom() | nil) ::
              String.t()

  @callback limit_offset_placeholders(
              limit_index :: pos_integer(),
              offset_index :: pos_integer()
            ) ::
              {limit_placeholder :: String.t(), offset_placeholder :: String.t()}

  @callback apply_filters(
              sql :: String.t(),
              params :: list(),
              filters :: [Lotus.Query.Filter.t()]
            ) ::
              {String.t(), list()}

  @callback apply_sorts(sql :: String.t(), sorts :: [Lotus.Query.Sort.t()]) :: String.t()

  @callback explain_plan(repo, sql :: String.t(), params :: list(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  # ---------------------------------------------------------------------------
  # Required callbacks — Safety & visibility
  # ---------------------------------------------------------------------------

  @callback builtin_denies(repo) ::
              [{String.t() | nil | Regex.t(), String.t() | Regex.t()}]

  @callback builtin_schema_denies(repo) :: [String.t() | Regex.t()]

  @callback default_schemas(repo) :: [String.t()]

  # ---------------------------------------------------------------------------
  # Required callbacks — Introspection
  # ---------------------------------------------------------------------------

  @callback list_schemas(repo) :: [String.t()]

  @callback list_tables(repo, schemas :: [String.t()], include_views? :: boolean()) ::
              [{schema :: String.t() | nil, table :: String.t()}]

  @callback get_table_schema(repo, schema :: String.t() | nil, table :: String.t()) ::
              [
                %{
                  name: String.t(),
                  type: String.t(),
                  nullable: boolean(),
                  default: String.t() | nil,
                  primary_key: boolean()
                }
              ]

  @callback resolve_table_schema(repo, table :: String.t(), schemas :: [String.t()]) ::
              String.t() | nil

  # ---------------------------------------------------------------------------
  # Required callbacks — Source identity
  # ---------------------------------------------------------------------------

  @callback source_type() :: :postgres | :mysql | :sqlite | :other | atom()
  @callback ecto_adapter() :: module() | nil
  @callback query_language() :: String.t()
  @callback limit_query(statement :: String.t(), limit :: pos_integer()) :: String.t()

  # ---------------------------------------------------------------------------
  # Optional callbacks — Source identity
  # ---------------------------------------------------------------------------

  @callback supports_feature?(feature :: atom()) :: boolean()
  @callback hierarchy_label() :: String.t()
  @callback example_query(table :: String.t(), schema :: String.t() | nil) :: String.t()

  # ---------------------------------------------------------------------------
  # Optional callbacks — Resource extraction
  # ---------------------------------------------------------------------------

  @doc """
  Extract the set of tables/relations a query will access.

  Used by `Lotus.Preflight` to check visibility rules before execution.
  Return `{:ok, MapSet}` with `{schema, table}` tuples, `{:error, reason}`,
  or `:skip` to allow the query without checking.

  Default (when not implemented): `:skip`.
  """
  @callback extract_accessed_resources(
              repo,
              query :: String.t(),
              params :: list(),
              opts :: keyword()
            ) ::
              {:ok, MapSet.t({String.t() | nil, String.t()})} | {:error, term()} | :skip

  # ---------------------------------------------------------------------------
  # Optional callbacks — SQL transformation & type mapping
  # ---------------------------------------------------------------------------

  @doc """
  Transform SQL query for dialect-specific syntax before variable substitution.

  Used for dialect-specific rewrites like INTERVAL syntax, CONCAT vs ||, etc.
  Return the transformed SQL string.

  Default (when not implemented): returns SQL unchanged.
  """
  @callback transform_sql(sql :: String.t()) :: String.t()

  @doc """
  Map a database-specific column type string to a Lotus internal type atom.

  Each dialect knows its own type system (e.g. Postgres `uuid`, MySQL `char(36)`,
  SQLite `INTEGER`).

  Default (when not implemented): `:text`.
  """
  @callback db_type_to_lotus_type(db_type :: String.t()) :: atom()

  @optional_callbacks [
    supports_feature?: 1,
    hierarchy_label: 0,
    example_query: 2,
    extract_accessed_resources: 4,
    transform_sql: 1,
    db_type_to_lotus_type: 1
  ]
end
