defmodule Lotus.Result do
  @enforce_keys [:columns, :rows]

  defstruct columns: [],
            rows: [],
            num_rows: nil,
            duration_ms: nil,
            command: nil,
            meta: %{}

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[term()]],
          num_rows: non_neg_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          command: String.t() | nil,
          meta: map()
        }

  def new(columns, rows, opts \\ []) do
    %__MODULE__{
      columns: columns || [],
      rows: rows || [],
      num_rows: Keyword.get(opts, :num_rows),
      duration_ms: Keyword.get(opts, :duration_ms),
      command: Keyword.get(opts, :command),
      meta: Keyword.get(opts, :meta, %{})
    }
  end
end
