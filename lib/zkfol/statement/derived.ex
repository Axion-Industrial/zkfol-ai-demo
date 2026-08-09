defmodule Zkfol.Statement.Derived do
  @moduledoc """
  I am the stage of a statement that has run: `Zkfol.Al`'s derivation,
  the facts the clauses established and the consumption between them.
  I am an answer already, needing no predicate, and the statement stops
  at me when no proof is wanted. `Zkfol.Lang` lowers the relations and
  lays me on the allocation born of that, which carries the statement to
  `Zkfol.Statement.Solved`.
  """

  use TypedStruct

  typedstruct enforce: true do
    field(:derivation, Zkfol.Derivation.t())
  end
end
