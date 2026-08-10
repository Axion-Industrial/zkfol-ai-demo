defmodule Zkfol.Statement.Lowered do
  @moduledoc """
  I am the stage of a statement whose relations have become a named
  predicate: `Zkfol.Lang`'s shape, standing on names, no row numbered.
  No witness models it yet; `Zkfol.Witness` runs the statement, and
  the allocation born of that run links me and carries the statement
  to `Zkfol.Statement.Solved`.
  """

  use TypedStruct

  typedstruct enforce: true do
    field(:shape, Zkfol.Lang.shape())
  end
end
