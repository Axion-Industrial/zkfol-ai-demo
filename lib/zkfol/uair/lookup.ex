defmodule Zkfol.Uair.Lookup do
  @moduledoc """
  I am the mode of a UAIR carrying BitPoly lookups: binary shadow columns
  and the tables declared on them, which ride into zinc+'s LogUp argument.
  Any other table still waits on zinc+, and its refusal lives with the
  backend that owes it.
  """

  use TypedStruct

  typedstruct enforce: true do
    field(:bin_columns, [[non_neg_integer()]], default: [])
    field(:lookups, [Zkfol.Uair.lookup()], default: [])
  end
end
