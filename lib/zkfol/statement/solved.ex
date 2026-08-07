defmodule Zkfol.Statement.Solved do
  @moduledoc """
  I am the stage of a statement that has both a predicate and a witness
  modelling it. Only I can be emitted and proved: `Zkfol.compile/2`
  reads its predicate and witness here. A run-produced witness carries
  its derivation; a hand-attached one carries none.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Derivation
  alias Zkfol.Interpretation

  typedstruct enforce: true do
    field(:pred, Ast.pred())
    field(:witness, Interpretation.t())
    field(:derivation, Derivation.t() | nil, default: nil, enforce: false)
  end
end
