defmodule Lotus.Adapter.Default do
  @moduledoc """
  Default adapter implementation for unsupported or unknown database adapters.

  Provides safe no-op implementations for adapter-specific functions and
  generic error formatting for database errors.
  """

  @behaviour Lotus.Adapter

  @impl true
  @doc "No-op: unsupported adapters cannot enforce read-only mode."
  def set_read_only(_repo), do: :ok

  @impl true
  @doc "No-op: unsupported adapters do not implement statement timeouts."
  def set_statement_timeout(_repo, _ms), do: :ok

  @impl true
  @doc "No-op: unsupported adapters do not implement search_path."
  def set_search_path(_repo, _path), do: :ok

  @impl true
  @doc """
  Formats common error types into strings. Falls back to `inspect/1`
  for unknown values.
  """
  def format_error(%{__exception__: true} = e), do: Exception.message(e)
  def format_error(%DBConnection.EncodeError{message: msg}), do: msg
  def format_error(%ArgumentError{message: msg}), do: msg
  def format_error(msg) when is_binary(msg), do: msg
  def format_error(other), do: "Database Error: #{inspect(other)}"

  @impl true
  @doc """
  Returns a generic SQL parameter placeholder (`"?"`).

  This keeps the query builder working even for unknown adapters,
  though actual binding semantics may differ.
  """
  def param_placeholder(_idx, _var, _type), do: "?"

  @impl true
  @doc "The default adapter does not handle any specific exceptions."
  def handled_errors, do: []
end
