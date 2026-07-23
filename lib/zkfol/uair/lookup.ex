defmodule Zkfol.Uair.Lookup do
  @moduledoc """
  I am the mode of a UAIR carrying BitPoly lookups: binary shadow columns
  and the tables declared on them, which ride into zinc+'s LogUp argument.
  Any other table still waits on zinc+.
  """

  use TypedStruct

  alias Zkfol.Refusal
  alias Zkfol.Uair
  alias Zkfol.ZincPlus

  typedstruct enforce: true do
    field(:bin_columns, [[non_neg_integer()]], default: [])
    field(:lookups, [Uair.lookup()], default: [])
  end

  @doc "I am my BitPoly lookups as the tuples the NIF takes."
  @spec tuples(t()) :: {:ok, [ZincPlus.lookup()]} | {:error, Refusal.t()}
  def tuples(%__MODULE__{lookups: lookups}) do
    Refusal.map(lookups, fn
      %{col: col, table: {:bit_poly, width, chunk}} -> {:ok, {col, width, chunk}}
      %{table: table} -> {:error, {:lookup_awaits_backend, %{table: table}}}
    end)
  end
end
