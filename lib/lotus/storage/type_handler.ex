defmodule Lotus.Storage.TypeHandler do
  @moduledoc """
  Behavior for implementing custom database type handlers.

  When you have custom database types (enums, domains, composite types), implement
  this behavior to teach Lotus how to cast values for that type.

  ## Example: Custom Enum Type

      defmodule MyApp.StatusEnumHandler do
        @behaviour Lotus.Storage.TypeHandler

        @valid_values ~w(active inactive pending archived)

        @impl true
        def cast(value, _opts) when value in @valid_values do
          {:ok, value}
        end

        def cast(value, _opts) when is_binary(value) do
          valid_values = ~w(active inactive pending archived)
          if String.downcase(value) in valid_values do
            {:ok, String.downcase(value)}
          else
            {:error, "Invalid status: must be one of \#{inspect(valid_values)}"}
          end
        end

        def cast(_value, _opts) do
          {:error, "Status must be a string"}
        end

        @impl true
        def requires_casting?(_value), do: false  # Let database validate
      end

  ## Registration

  Register your handler in config/config.exs:

      config :lotus, :type_handlers, %{
        "status_enum" => MyApp.StatusEnumHandler,
        "my_custom_domain" => MyApp.CustomDomainHandler
      }

  The key should match the exact database type name from information_schema.columns.data_type.

  ## Example: UUID v7 Custom Handler

      defmodule MyApp.UUIDv7Handler do
        @behaviour Lotus.Storage.TypeHandler

        @impl true
        def cast(value, _opts) do
          case Unid.UUID.cast(value) do  # Using Unid library
            {:ok, uuid_string} ->
              case Unid.UUID.dump(uuid_string) do
                {:ok, binary} -> {:ok, binary}
                :error -> {:error, "Invalid UUID v7 format"}
              end
            :error ->
              {:error, "Invalid UUID v7"}
          end
        end

        @impl true
        def requires_casting?(_value), do: true  # Always cast to binary
      end

  ## Example: PostgreSQL Composite Type

      defmodule MyApp.AddressHandler do
        @behaviour Lotus.Storage.TypeHandler

        @impl true
        def cast(value, _opts) when is_map(value) do
          # Validate required fields
          if Map.has_key?(value, "street") and Map.has_key?(value, "city") do
            {:ok, value}
          else
            {:error, "Address must have street and city fields"}
          end
        end

        def cast(value, _opts) when is_binary(value) do
          case Lotus.JSON.decode(value) do
            {:ok, map} when is_map(map) -> cast(map, %{})
            _ -> {:error, "Invalid JSON for address"}
          end
        rescue
          _ -> {:error, "Invalid address format"}
        end

        def cast(_value, _opts) do
          {:error, "Address must be a map or JSON string"}
        end

        @impl true
        def requires_casting?(_value), do: true
      end
  """

  @doc """
  Cast a value from web input (typically string) to database-native format.

  Returns `{:ok, casted_value}` on success or `{:error, reason}` on failure.

  ## Parameters

  - `value`: The input value to cast (usually a string from the web UI)
  - `opts`: A map with optional metadata like:
    - `:table` - The table name
    - `:column` - The column name
    - `:source_module` - The database source module
  """
  @callback cast(value :: term(), opts :: map()) :: {:ok, term()} | {:error, String.t()}

  @doc """
  Determine if this type requires explicit casting or can be passed through.

  Return `true` for types that need conversion (e.g., UUID to binary).
  Return `false` for types that can be passed as-is (e.g., enums, text).

  This is used to optimize query generation by skipping unnecessary type casts.
  """
  @callback requires_casting?(value :: term()) :: boolean()
end
