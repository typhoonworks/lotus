defmodule Lotus.Preflight.Relations do
  @moduledoc """
  Manages preflight relations stored in the process dictionary.

  This module provides a clean interface for storing and retrieving
  relations discovered during SQL preflight authorization, which are
  later used for column-level visibility policies.
  """

  @process_key :lotus_preflight_relations

  @doc """
  Stores the list of relations in the process dictionary.

  These relations are discovered during preflight authorization
  and will be used later for column visibility checks.
  """
  @spec put([{String.t(), String.t()}]) :: :ok
  def put(relations) when is_list(relations) do
    Process.put(@process_key, relations)
    :ok
  end

  @doc """
  Retrieves the list of relations from the process dictionary.

  Returns an empty list if no relations have been stored.
  """
  @spec get() :: [{String.t(), String.t()}]
  def get do
    Process.get(@process_key) || []
  end

  @doc """
  Retrieves and clears the list of relations from the process dictionary.

  This is typically called after the relations have been consumed
  to ensure they don't leak to subsequent operations.
  """
  @spec take() :: [{String.t(), String.t()}]
  def take do
    relations = get()
    clear()
    relations
  end

  @doc """
  Clears the stored relations from the process dictionary.
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@process_key)
    :ok
  end
end
