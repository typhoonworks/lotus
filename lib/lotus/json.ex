defmodule Lotus.JSON do
  @moduledoc false

  # Delegates to JSON in Elixir v1.18+ or Jason for earlier versions

  cond do
    Code.ensure_loaded?(JSON) ->
      defdelegate decode!(data), to: JSON
      defdelegate encode!(data), to: JSON
      defdelegate encode_to_iodata!(data), to: JSON

      # Create an alias to the actual JSON.Encoder protocol
      def encoder, do: JSON.Encoder

    Code.ensure_loaded?(Jason) ->
      defdelegate decode!(data), to: Jason
      defdelegate encode!(data), to: Jason
      defdelegate encode_to_iodata!(data), to: Jason

      # Create an alias to the actual Jason.Encoder protocol
      def encoder, do: Jason.Encoder

    true ->
      message = "Missing a compatible JSON library, add `:jason` to your deps."

      IO.warn(message, Macro.Env.stacktrace(__ENV__))
  end
end
