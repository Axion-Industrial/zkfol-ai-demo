defmodule Zkfol.Statement.Solved do
  @moduledoc """
  I am the stage of a statement that has both a predicate and a witness
  modelling it, the predicate linked: every row numbered. Only I can be
  emitted and proved: `Zkfol.compile/2` reads its predicate and witness
  here. A run-produced witness carries its lay -- the one value saying
  how the allocation placed the derivation; a hand-attached witness
  carries none.
  """

  use TypedStruct

  alias Zkfol.Ast
  alias Zkfol.Interpretation
  alias Zkfol.Lay

  typedstruct enforce: true do
    field(:pred, Ast.pred())
    field(:witness, Interpretation.t())
    field(:lay, Lay.t() | nil, default: nil, enforce: false)
  end
end
